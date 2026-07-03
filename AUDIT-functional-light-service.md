# Audit tecnico completo — functional-light-service v0.5.4

> Audit indipendente condotto sul codice reale di `lib/` (1.601 righe) e `spec/` (54 file di spec).
> **Ogni finding contrassegnato [VERIFICATO] è stato riprodotto eseguendo codice contro la libreria**
> (Ruby 3.4.9 mingw-ucrt, dry-inflector 1.3.1, i18n 1.15.2). I numeri di performance sono misurati
> con `benchmark-ips`, non stimati. Data audit: 2026-07-03.

---

## 1. Executive summary

1. **[Critico]** Gli hook dichiarativi `before_actions`/`after_actions` funzionano **solo alla prima chiamata** dell'Organizer: `with` li consuma e li azzera sulla classe (`organizer.rb:22-30`). Riprodotto: prima call = −9, seconda call = 1. In multi-thread (Puma/Sidekiq) è anche una race condition.
2. **[Alto]** `Context#fetch` viola il contratto di `Hash#fetch`: non solleva mai `KeyError` e **scrive nel context durante una lettura** (`context.rb:130-136`). Riprodotto.
3. **[Alto]** Gli alias sono asimmetrici: la lettura traduce alias→chiave originale, la scrittura no. Scrivere su un alias produce un valore invisibile in lettura e due chiavi divergenti nell'hash (`context.rb:113-128`). Riprodotto.
4. **[Alto]** Il motore di pattern matching custom (`enum.rb`) costa **~250-300x** rispetto al `case/in` nativo di Ruby (misurato: `Option#value_or` 28-31k i/s vs 6,7-7M i/s). È costo CPU (`binding.eval`, `Matcher` + `instance_eval`, `Struct.new` per chiamata nei guard), non GC.
5. **[Alto]** Il rollback è incompleto se un'action compare più volte nella pipeline: `actions.index(current_action)` trova la prima occorrenza (`with_reducer.rb:70`). Riprodotto: rollback eseguito solo su 1 action su 3.

Nota di metodo: il profilo dei costi è **CPU-bound** (reflection, eval, dispatch), non GC-bound. Un'estensione nativa C/Rust **non è giustificata** (vedi §2.6-F4); i fix in Ruby puro eliminano la quasi totalità dell'overhead.

---

## 2. Findings dettagliati

### Area 1 — Concorrenza e thread-safety

#### 1.1 — Gli hook di classe vengono consumati e azzerati da `with`: persi dalla seconda chiamata, race in multi-thread
- **Severità**: Critico
- **Posizione**: `lib/functional-light-service/organizer.rb:22-30`
- **Descrizione**: `with` copia `@before_actions`/`@after_actions` nel context e poi **azzera le variabili d'istanza di classe** (`@before_actions = nil`). Un organizer che dichiara gli hook con il macro `before_actions` (a load-time, una volta) li perde definitivamente dopo la prima `call`. L'azzeramento esiste per servire `Testing::ContextFactory` (che appende un hook temporaneo via `append_before_actions`, `testing/context_factory.rb:11-22`), ma il costo è la rottura del caso d'uso di produzione.
- **Scenario di fallimento** [VERIFICATO]:
  ```ruby
  class Org1
    extend FunctionalLightService::Organizer
    before_actions ->(ctx) { ctx.number -= 10 if ctx.current_action == AddOne }
    def self.call(n) = with(:number => n).reduce([AddOne])
  end
  Org1.call(0).fetch(:number)  # => -9  (hook applicato)
  Org1.call(0).fetch(:number)  # =>  1  (hook PERSO)
  ```
  Interleaving multi-thread: il thread A esegue `with` e azzera `@before_actions`; il thread B, entrato dopo il `dup` di A ma prima del proprio `if @before_actions`, legge `nil` e perde gli hook anche alla "prima" chiamata. Nessuna sincronizzazione presente. La spec `spec/acceptance/before_actions_spec.rb:54-58` chiama l'organizer **una sola volta**, quindi il bug non è mai stato osservato dalla suite.
- **Fix proposto**: `with` deve solo *leggere* lo stato di classe: `data[:_before_actions] = @before_actions.dup if @before_actions` senza azzerare. Per il ContextFactory, sostituire il meccanismo "appendi sulla classe + consuma" con un hook passato per-chiamata (es. `organizer.call(ctx, _before_actions: [...])` interno al factory) oppure rimuovere l'hook nel proprio `ensure`. Trade-off: nessuna rottura per gli utenti; da adattare `ContextFactory` e la sua spec. Rischio di regressione basso e circoscritto al testing helper.

#### 1.2 — La classe Action trattiene l'ultimo context in `@ctx`: race tra thread e retention di memoria
- **Severità**: Alto
- **Posizione**: `lib/functional-light-service/action.rb:42` (scrittura), `action.rb:33-35` (macro `ctx`, dead code)
- **Descrizione**: ad ogni `execute`, l'Action scrive `@ctx = action_context` **sulla classe** (le classi sono globali e condivise tra thread). Due job Sidekiq che eseguono la stessa Action si sovrascrivono a vicenda `@ctx`; inoltre la classe trattiene per sempre un riferimento all'ultimo context (e a tutto ciò che contiene: record, connessioni, payload), impedendone il GC. Il macro `ctx(*args)` che dovrebbe leggerlo non è usato da nessuna parte (grep su spec/ e README: zero usi).
- **Scenario di fallimento** [VERIFICATO]:
  ```ruby
  AddOne.execute(:number => 5)
  AddOne.instance_variable_get(:@ctx)  # => FunctionalLightService::Context({number: 6}, ...)
  # resta vivo finché vive la classe = per sempre
  ```
- **Fix proposto**: eliminare la riga `@ctx = action_context` e il macro `ctx` (dead code). Zero impatto sull'API usata; −6 righe.

#### 1.3 — Memoizzazioni `||=` non sincronizzate in Configuration e Null
- **Severità**: Basso
- **Posizione**: `lib/functional-light-service/configuration.rb:7-13`, `lib/functional-light-service/functional/null.rb:12-14`
- **Descrizione**: `@localization_adapter ||= ...` e `@instance ||= new([])` possono produrre due istanze sotto race. Entrambi gli oggetti sono stateless/equivalenti (`Null#==` confronta per `null?`), quindi l'effetto è benigno.
- **Scenario di fallimento**: due thread al primo accesso concorrente ottengono istanze diverse; nessun comportamento errato osservabile. "Da verificare" solo come igiene.
- **Fix proposto**: assegnare le default a load-time (costante) o proteggere con `Mutex`. Priorità bassa.

#### 1.4 — Il Context mutabile condiviso è sicuro *solo* finché resta per-chiamata
- **Severità**: Medio (rischio architetturale, non bug attivo)
- **Posizione**: `lib/functional-light-service/context.rb` (tutta la classe)
- **Descrizione**: il design muta il Context in-place lungo la pipeline. Non è una race di per sé (ogni `call` crea il suo context), ma qualunque riuso — context passato a più organizer in thread diversi, context memorizzato in una costante, o il caso 1.2 — diventa immediatamente stato condiviso non protetto. Il contratto "il context non si condivide tra thread" non è documentato.
- **Fix proposto**: documentare esplicitamente il contratto nel README; in prospettiva vedi Area 5 (F1).

---

### Area 2 — Correttezza / bug

#### 2.1 — `Context#fetch` non solleva mai `KeyError` e scrive durante la lettura
- **Severità**: Alto
- **Posizione**: `lib/functional-light-service/context.rb:130-136`
- **Descrizione**: l'override è `self[key] ||= block_given? ? super(key, &blk) : super`. Due violazioni del contratto di `Hash#fetch`: (a) `fetch(:mancante)` senza default dovrebbe sollevare `KeyError`, invece `super` riceve `default = nil` e ritorna `nil`; (b) l'operatore `||=` **scrive la chiave nel context** — un metodo di lettura con side-effect permanente. Gli accessor generati (`context.rb:108`) usano `fetch`, quindi ogni lettura di chiave con valore `nil`/`false` esegue una scrittura.
- **Scenario di fallimento** [VERIFICATO]:
  ```ruby
  ctx = FunctionalLightService::Context.make({})
  ctx.fetch(:missing)   # => nil (atteso: KeyError)
  ctx.keys              # => [:missing]  ← la lettura ha creato la chiave
  ```
  (Nota: `fetch(:flag, true)` con `:flag => false` esistente NON sovrascrive col default — `Hash#fetch` ritorna il valore esistente anche se falsy. Verificato e non riproducibile come bug.)
- **Fix proposto**: rimuovere l'override o ridurlo alla sola traduzione alias (`super(aliases.key(key) || key, ...)`) preservando la semantica nativa. **Breaking change dichiarato**: chi si affida a `fetch(:x)` ⇒ `nil` su chiave mancante (il README stesso usa `result.fetch(:number)` su chiavi esistenti, che resta valido). Rischio medio: da accompagnare con spec di contratto.

#### 2.2 — Alias asimmetrici: la scrittura su un alias è invisibile in lettura
- **Severità**: Alto
- **Posizione**: `lib/functional-light-service/context.rb:113-128` (`assign_aliases`, `[]`), `[]=` non overridato
- **Descrizione**: `[]` traduce l'alias verso la chiave originale (`aliases.key(key) || key`), ma `[]=` scrive la chiave letterale. Dopo `assign_aliases(:codice_fiscale => :cf)`, scrivere `ctx[:cf] = "NUOVO"` crea una chiave `:cf` che la lettura `ctx[:cf]` non vedrà mai (risolve su `:codice_fiscale`). L'hash contiene due verità divergenti. Inoltre `assign_aliases` copia fisicamente i valori sulle chiavi alias (`context.rb:116-118`), ridondante rispetto alla traduzione in lettura e ulteriore fonte di divergenza.
- **Scenario di fallimento** [VERIFICATO]:
  ```ruby
  ctx = FunctionalLightService::Context.make(:codice_fiscale => "ABC")
  ctx.assign_aliases(:codice_fiscale => :cf)
  ctx[:cf] = "NUOVO"
  ctx[:cf]    # => "ABC"  (la scrittura è persa)
  ctx.to_h    # => {codice_fiscale: "ABC", cf: "NUOVO"}
  ```
- **Fix proposto**: overridare anche `[]=` con la stessa traduzione, ed eliminare la copia fisica in `assign_aliases` (con inverse-hash precomputato, vedi F3-Area 3). Trade-off: chi (impropriamente) leggeva la chiave alias via `to_h` vede il cambiamento; documentare gli alias come nomi alternativi, non copie.

#### 2.3 — Rollback parziale quando un'action compare più volte nella pipeline
- **Severità**: Alto
- **Posizione**: `lib/functional-light-service/organizer/with_reducer.rb:69-74`
- **Descrizione**: per decidere quali action ri-percorrere, `reversable_actions` usa `actions.index(@context.current_action)`. `current_action` è la *classe* dell'action: se la stessa classe compare due volte e il fallimento avviene alla seconda occorrenza, `index` ritorna la prima ⇒ il rollback copre solo il prefisso sbagliato. Inoltre, se il fallimento avviene dentro una lambda-step (`execute(...)`), `current_action` è l'ultima *Action* eseguita, non lo step corrente.
- **Scenario di fallimento** [VERIFICATO]:
  ```ruby
  with(ctx).reduce([RollB, RollA, RollB])  # fail_with_rollback! nella SECONDA RollB
  # eseguite: B, A, B — rollback attesi: B, A, B — rollback effettivi: [:b] (solo il primo prefisso)
  ```
- **Fix proposto**: tracciare l'indice dell'azione corrente durante il `reduce` (variabile locale del loop passata al rescue) invece di ricostruirlo a posteriori con `index`. Nessun breaking change; rischio basso.

#### 2.4 — Accessor silenziosamente non definiti quando la chiave collide con un metodo di Hash/Context
- **Severità**: Medio
- **Posizione**: `lib/functional-light-service/context.rb:106` (`next if respond_to?(key.to_sym)`)
- **Descrizione**: se un'action dichiara `expects :size` (o `:count`, `:key`, `:merge`, `:message`…), l'accessor non viene definito perché `Context` (che è un `Hash`) risponde già a quel nome. Dentro l'action, `ctx.size` ritorna il numero di chiavi dell'hash, non il valore — **senza alcun errore o warning**. `ReservedKeysVerifier` protegge solo `:message`, `:error_code`, `:current_action` (`key_verifier.rb:113-115`).
- **Scenario di fallimento** [VERIFICATO]:
  ```ruby
  class UsesSize
    extend FunctionalLightService::Action
    expects :size
    executed { |ctx| ctx[:observed] = ctx.size }
  end
  UsesSize.execute(:size => 999)[:observed]  # => 1 (Hash#size), non 999
  ```
- **Fix proposto**: in `define_accessor_methods_for_keys`, sollevare (o loggare a livello warn) quando la chiave collide con un metodo esistente invece di saltare in silenzio. Trade-off: chi oggi ha collisioni latenti vedrà l'errore — che è esattamente lo scopo.

#### 2.5 — `skip_remaining!` nei costrutti annidati viene resettato e cancella l'outcome
- **Severità**: Medio
- **Posizione**: `lib/functional-light-service/organizer/scoped_reducable.rb:5-7`, `lib/functional-light-service/context.rb:45-48`
- **Descrizione**: `scoped_reduce` chiama `reset_skip_remaining!` prima e dopo ogni sotto-riduzione. Due effetti non documentati: (a) uno `skip_remaining!` dentro gli step di `iterate` salta solo il resto degli step *di quell'item* — l'iterazione continua con l'item successivo; (b) `reset_skip_remaining!` non resetta solo il flag: **sovrascrive l'intero `@outcome`** con un `Success` vuoto, cancellando qualunque messaggio impostato con `succeed!`/`skip_remaining!`.
- **Scenario di fallimento** [VERIFICATO]:
  ```ruby
  # iterate su [1,2,3]; skip_remaining! quando counter==2:
  result[:seen]  # => [1, 3] — il 3 è stato processato: lo skip non ha fermato l'iterazione
  # e separatamente:
  ctx.succeed!("fatto bene"); ctx.reset_skip_remaining!; ctx.message  # => ""
  ```
- **Fix proposto**: separare il reset del flag dal reset dell'outcome (`@skip_remaining = false` senza toccare `@outcome`), e documentare la semantica per-scope dello skip (o offrire `skip_all!`). Trade-off: chi dipende dal reset del messaggio (improbabile) cambia comportamento.

#### 2.6 — `fail!` muta l'hash di opzioni del chiamante
- **Severità**: Medio
- **Posizione**: `lib/functional-light-service/context.rb:69` (`delete`), `lib/functional-light-service/localization_adapter.rb:26` (`merge!`)
- **Descrizione**: `fail!` fa `options_or_error_code.delete(:error_code)` sull'hash passato dall'utente, e l'adapter i18n fa `i18n_options.merge!(type)`. Input del chiamante modificato in-place.
- **Scenario di fallimento** [VERIFICATO]:
  ```ruby
  opts = { :error_code => 500 }
  ctx.fail!("boom", opts)
  opts  # => {} — un secondo fail!("x", opts) perde l'error_code
  ```
- **Fix proposto**: `options = options_or_error_code.dup` in testa a `fail!`; `i18n_options.merge(type)` senza bang. Rischio nullo.

#### 2.7 — Quattro modi di fallire e control flow non-locale (`throw`/`raise` come flusso)
- **Severità**: Medio
- **Posizione**: `lib/functional-light-service/action.rb:50` (`catch(:jump_when_failed)`), `lib/functional-light-service/context.rb:83-91`
- **Descrizione**: esistono `fail!` (continua l'esecuzione dell'action corrente), `fail_and_return!` (`throw` catturato in `execute`), `fail_with_rollback!` (eccezione catturata nel reducer), più il ritorno di `Failure(...)` monadico per il codice utente. Il `throw` è un salto non-locale invisibile nello stack; chiamare `fail_and_return!` su un context fuori da un `execute` produce `UncaughtThrowError`; `fail_with_rollback!` fuori da un organizer propaga `FailWithRollbackError` (workaround documentato nel README con `organized_by.nil?`, riga ~805-824). Nessuna guida su quale usare quando.
- **Scenario di fallimento**: `FunctionalLightService::Context.make({}).fail_and_return!("x")` ⇒ `UncaughtThrowError` (deducibile dal codice; non è un percorso d'uso normale).
- **Fix proposto**: documentare una gerarchia chiara (`fail_and_return!` come default nelle action; `fail!` solo quando serve continuare; rollback per compensazioni) e in una futura major valutare la deprecazione di uno dei due. Il `catch/throw` in sé può restare: è il male minore rispetto alle eccezioni per il flusso ordinario, ma va nascosto dietro un'unica API.

#### 2.8 — `Null`: firma di `respond_to?` errata, `method_missing` che nasconde i typo, monkey-patch globale di `Object`
- **Severità**: Basso (ma con effetto sistemico)
- **Posizione**: `lib/functional-light-service/functional/null.rb:61-65`, `null.rb:47-51`, `lib/functional-light-service/functional/maybe.rb:1-9`
- **Descrizione**: (a) `def respond_to?(m)` omette il parametro `include_all`: qualunque chiamata a due argomenti esplode; (b) manca `respond_to_missing?` (la convenzione Ruby corretta); (c) con `@methods` vuoto, `Null.instance` risponde a *tutto*: un typo su un metodo si propaga come `Null` silenzioso invece di un `NoMethodError`; (d) `maybe.rb` monkey-patcha `Object` con `null?`/`some?` per tutti gli oggetti del processo — invasivo per una gem.
- **Scenario di fallimento** [VERIFICATO]:
  ```ruby
  Null.instance.respond_to?(:foo, true)  # => ArgumentError (given 2, expected 1)
  ```
- **Fix proposto**: correggere la firma (`def respond_to_missing?(m, include_all = false)`); valutare la deprecazione dell'intero duo `Maybe()`/`Null` a favore di `Option` (vedi Area 4-F3).

#### 2.9 — `Context` eredita da `Hash`: le operazioni Hash degradano silenziosamente il tipo
- **Severità**: Basso
- **Posizione**: `lib/functional-light-service/context.rb:3`
- **Descrizione**: `select`, `reject`, `merge`, `slice` ecc. ritornano `Hash` puro: outcome, alias e stato di skip spariscono senza errore.
- **Scenario di fallimento** [VERIFICATO]: `ctx.select { true }.class # => Hash` (né `success?` né `message` disponibili).
- **Fix proposto**: nel breve, documentare; nel lungo, composizione invece di ereditarietà (Area 5-F2, breaking).

#### 2.10 — Finding minori verificati o da verificare
- **`Some(nil)` è costruibile** [VERIFICATO] — `option.rb`: nessuna validazione in `Some.new(nil)`; `Option.some?(nil)` correttamente dà `None`, ma il costruttore diretto no. Severità Basso. Fix: raise o normalizzazione in `Some#initialize`.
- **Reserved keys incomplete** — `key_verifier.rb:113-115` non include `:callback`, `:_before_actions`, `:_after_actions`, `:_aliases`, tutte chiavi che l'infrastruttura scrive nel context (`with_callback.rb:13`, `organizer.rb:20-29`). Un'action con `expects :callback` o dati utente con quelle chiavi collidono. Severità Basso, *da verificare* lo scenario completo. Fix: estendere la lista.
- **`EnumBuilder#method_missing` senza `respond_to_missing?`** e ridefinizione di una variante ⇒ `NoMethodError` criptico (`enum.rb:116-122`). Severità Basso.
- **`attr_accessor :outcome`** (`context.rb:6`): chiunque può assegnare `ctx.outcome = "banana"` e far esplodere `success?` a distanza. Severità Basso. Fix: `attr_reader` + writer privato.

---

### Area 3 — Performance

> Metodo: micro-benchmark `benchmark-ips` eseguiti su Ruby 3.4.9 (build mingw-ucrt **senza YJIT**).
> Tutti i costi sotto sono **CPU** (reflection, eval, creazione classi), non GC: la distinzione è
> verificata dal fatto che i rapporti restano identici tra run e che le operazioni dominanti
> (eval/caller/define_method) non allocano in modo significativo rispetto al lavoro utile.

#### 3.1 — Il motore `match` custom costa ~250-300x rispetto al `case/in` nativo
- **Severità**: Alto (per chi usa Option/Result in hot path; irrilevante per uso sporadico)
- **Posizione**: `lib/functional-light-service/functional/enum.rb:135-170` (match), `enum.rb:176-182` (guard), `option.rb:31-73` (tutte le operazioni Option passano da `match`)
- **Descrizione**: ogni `match` paga: `block.binding.eval('self')` (`enum.rb:136`), creazione `Matcher` + `instance_eval` del blocco, exhaustiveness-check con `collect/uniq/sort` per chiamata, e nei guard **`Struct.new(*args)` crea una classe per chiamata** (`enum.rb:178-180`). `Option#map`, `#fmap`, `#value_or`, `#+`, `Result#or/and/+` usano tutti `match`. `Result#map/bind` invece no — ed è infatti 100x più veloce.
- **Misure** (`benchmark-ips`):
  | Operazione | i/s | vs baseline |
  |---|---|---|
  | `Option#value_or` (match engine) | ~29k | **~264-300x più lento** |
  | `case/in` nativo equivalente | ~6,7-7,0M | baseline |
  | `Result#+` (match con guard ⇒ `Struct.new`/call) | ~24-25k | **~75-76x più lento** della somma diretta |
  | `Result#map` (via `bind`, senza match) | ~1,02M | solo 1,8x più lento della lambda diretta |
- **Scenario**: pipeline ETL che chiama `value_or` su 1M di Option: ~35 secondi di solo overhead di match contro ~0,15s col `case/in`.
- **Fix proposto**: reimplementare le operazioni di `Option`/`Result` con dispatch diretto (`is_a?`/polimorfismo), mantenendo `match` come API pubblica ma riscritta sopra `case/in` con exhaustiveness garantita da `else raise MatchError`. I benchmark sopra sono il criterio di accettazione. Trade-off: il DSL `match` con guard `where {}` va mappato su pattern guard nativi; le spec `spec/lib/enum_spec.rb` proteggono il comportamento.

#### 3.2 — `Organizer.with` paga `caller(1..1)` + `methods.include?(:call)` a ogni chiamata (e a ogni item di `iterate`)
- **Severità**: Alto
- **Posizione**: `lib/functional-light-service/organizer.rb:19`, `lib/functional-light-service/organizer/verify_call_method_exists.rb:7-11`
- **Descrizione**: `VerifyCallMethodExists.run(self, caller(1..1).first)` è un deprecation-check (il commento dice "should be removed eventually") che a ogni `with` cattura e formatta uno stack frame (`caller` è notoriamente costoso) e alloca l'array completo dei metodi della classe (`klass.methods.include?(:call)` invece di `respond_to?(:call)`). `ScopedReducable#scoped_reduce` richiama `organizer.with(ctx)` **per ogni item** di `iterate`/`reduce_if`/`reduce_until` (`scoped_reducable.rb:6`).
- **Misure**: `caller(1..1)` + regex + `methods.include?` ≈ 58k i/s (~17 µs/call) contro `respond_to?(:call)` ≈ 10,6M i/s: **~180-184x**. Su un `iterate` da 100k item: ~1,7s di puro overhead di deprecation-check.
- **Fix proposto**: rimuovere il check (è uno shim transitorio) o eseguirlo una sola volta per classe (flag memoizzato). Rischio zero.

#### 3.3 — Accessor singleton definiti su ogni Context a ogni `execute`
- **Severità**: Medio
- **Posizione**: `lib/functional-light-service/context.rb:102-111`, chiamato da `action.rb:48`
- **Descrizione**: ogni `execute` definisce reader/writer come **singleton method sul singolo context** (`define_singleton_method`). Costo CPU per definizione + materializzazione della singleton class per ogni context.
- **Misure**: creazione context + accessor per 3 chiavi ≈ 58k i/s contro 335k i/s senza accessor: **~5,5-5,8x** sul costo di setup per action.
- **Fix proposto**: sostituire con `method_missing` + `respond_to_missing?` sul Context (dispatch dinamico ma senza definizione per-istanza), oppure generare i metodi **una volta per classe Action** su un modulo cache-ato (chiavi note a load-time da `expects`/`promises`). La seconda opzione preserva la velocità di chiamata. Attenzione a combinare col fix 2.4.

#### 3.4 — `Context#[]` fa un reverse-scan O(n) degli alias a ogni lettura
- **Severità**: Medio
- **Posizione**: `lib/functional-light-service/context.rb:125-128`
- **Descrizione**: `aliases.key(key)` scandisce l'hash degli alias per valore a **ogni** lettura di **ogni** chiave, anche quando gli alias non c'entrano.
- **Misure**: `ctx[:b]` con 1 alias attivo ≈ 3,9M i/s contro 13,2M i/s di `Hash#[]` puro: **~3,2-3,4x** su ogni singolo accesso.
- **Fix proposto**: precomputare l'hash inverso in `assign_aliases` (`@inverse_aliases = aliases.invert`) e fare `@inverse_aliases[key] || key`; bypass totale quando `@aliases` è vuoto (`return super if @aliases.nil?`). Rischio nullo.

#### 3.5 — Overhead per-item di `iterate` e allocazioni evitabili
- **Severità**: Medio
- **Posizione**: `lib/functional-light-service/organizer/iterate.rb:12-19`, `lib/functional-light-service/organizer/with_reducer.rb:22-28`
- **Descrizione**: (a) `Dry::Inflector.new` + `singularize` a ogni invocazione della lambda (basta farlo una volta in `run`); (b) ogni item paga l'intero stack `with` → `VerifyCallMethodExists` → `WithReducerFactory.make` → `WithReducer.new` → `Context.make`; (c) quando non c'è `around_each`, `around_each_handler` crea una **classe anonima** per ogni WithReducer (`Class.new` con `def self.call`).
- **Misure** (end-to-end): `Organizer.call` con 1 action ≈ 18k i/s, cioè **~55 µs a chiamata**, ~200x il lavoro utile equivalente. Per servizi con I/O è rumore; dentro `iterate` su collezioni grandi domina il tempo totale.
- **Fix proposto**: inflettere fuori dalla lambda; sostituire la classe anonima con un modulo costante (`NoopHandler = ->(_ctx, &blk) { blk.call }` o modulo con `.call`); costruire un reducer leggero per gli step annidati che non ripassi da `with`. Beneficio atteso: la maggior parte dei 55 µs (misurare dopo, stesso benchmark).

#### 3.6 — YJIT e `frozen_string_literal`: benefici reali ma da ridimensionare
- **Severità**: Basso (informativo)
- **Posizione**: build locale; tutti i file di `lib/` (nessuno ha il magic comment — verificato con grep)
- **Descrizione**: la roadmap precedente indicava "+30-100% con YJIT". Verificato sul campo: **la build Ruby di sviluppo (3.4.9 mingw-ucrt) è compilata senza supporto YJIT** (`ruby --yjit` ⇒ "Ruby was built without YJIT support"). Inoltre YJIT accelera dispatch ripetitivo e codice monomorfico, ma **non salva** `binding.eval`, `caller`, `define_singleton_method` per-call: i fix 3.1-3.5 vengono prima. `frozen_string_literal: true` è assente ovunque: beneficio modesto (le stringhe in hot path sono soprattutto messaggi di log) ma gratuito.
- **Fix proposto**: aggiungere il magic comment ovunque (rubocop lo automatizza); abilitare YJIT solo dove la piattaforma lo supporta (produzione Linux), **dopo** i fix CPU, e rimisurare con lo stesso `bench.rb`.

---

### Area 4 — Codice superfluo / semplificazione

#### F1 — Dead code certo: macro `ctx` e scrittura `@ctx`
- **Severità**: Basso — **Posizione**: `action.rb:33-35, 42`
- Nessun uso in lib/, spec/ o README (verificato con grep). Eliminazione: −6 righe, chiude anche il finding 1.2.

#### F2 — `VerifyCallMethodExists`: shim transitorio dichiarato, mai rimosso
- **Severità**: Medio — **Posizione**: `organizer/verify_call_method_exists.rb` (30 righe) + `organizer.rb:19`
- Il commento nel file stesso dice "This should be removed eventually". Rimozione: −30 righe, −17 µs per call (finding 3.2), meno una spec (`not_having_call_method_warning_spec.rb`).

#### F3 — Doppio sistema per l'assenza di valore: `Option` monadico E `Maybe()`/`Null`
- **Severità**: Medio — **Posizione**: `functional/option.rb` vs `functional/maybe.rb` + `functional/null.rb` (~90 righe)
- Due paradigmi per lo stesso problema, di cui uno (`Null`) monkey-patcha `Object` e nasconde i typo (finding 2.8). Deprecare `Maybe`/`Null` a favore di `Option`: −90 righe, API più coerente. **Breaking** per chi usa `Maybe()`: deprecation warning per una minor, rimozione in major.

#### F4 — Il motore enum (250 righe) è sostituibile con `case/in` + `Data.define` di Ruby 3.2
- **Severità**: Alto (per manutenibilità) — **Posizione**: `functional/enum.rb` (250 righe; la nota della sessione precedente diceva "~6000 righe": errato, sono 250)
- `Success(:s)`/`Failure(:f)`/`Some(:s)`/`None()` sono definibili come classi concrete (o `Data.define`), con `match` reimplementato sopra `case/in`. Elimina `method_missing` builder, `binding.eval`, `Kernel.eval` in `impl` (`enum.rb:246`), `Struct.new` nei guard. Stima: −200 righe nette, chiude i finding 3.1 e 2.10-c. Rischio: il DSL pubblico `match do Some() {...} end` va preservato come facciata; le spec `enum_spec.rb`, `option_spec.rb`, `result_spec.rb` sono la rete di sicurezza.

#### F5 — Minori
- Deprecation warning per `include` (organizer.rb:8-14, action.rb:8-14): rimuovibili in una major.
- gemspec: `i18n` e `dry-inflector` dichiarate sia runtime che development (ridondante); `test_files` è deprecato in RubyGems recenti; il magic comment `# -*- encoding: utf-8 -*-` è inutile da Ruby 2.0.
- Operatori esotici su Result/Option: `>=` come alias di `try`, `<<` di `pipe`, `>>` di `map` (`result.rb:23-37, 91`) — un operatore di confronto che esegue una lambda è una trappola di leggibilità; candidati a deprecazione.

**Impatto complessivo stimato dell'area**: da ~1.600 a ~1.100-1.200 righe, con superficie API più piccola e nessuna perdita funzionale per gli usi documentati.

---

### Area 5 — Design e paradigma

#### F1 — Il conflitto FP/mutabilità è reale, ma la soluzione giusta è dichiararlo, non forzare l'immutabilità
- **Severità**: Medio (concettuale)
- **Posizione**: trasversale (`context.rb`, `functional/*`)
- **Descrizione**: il Context è un Hash mutabile con stato interno (`@outcome`, `@skip_remaining`); le monadi promettono composizionalità che il flusso `ctx.try! { ... }.map_err { ctx.fail!(...) }` nega subito (side-effect dentro la catena). In pratica **il Result dentro al Context non è usato come monade ma come "esito ricco"** (message + error_code). La referential transparency non c'è e non ci sarà.
- **Direzione proposta** (coerente col vincolo di preservare il metodo): assumere esplicitamente il modello **"Functional Core, Imperative Shell"**: il Context è la shell imperativa (mutabile, per-chiamata, non condivisa — da documentare, finding 1.4); le monadi Option/Result restano per i **valori di ritorno del dominio dentro le singole Action**, dove la composizione locale (`map`/`bind`) ha senso. Rinunciare alle API che fingono composizione sul Context. Un Context immutabile (ogni action ritorna un nuovo context) sarebbe FP "vera" ma è una riscrittura breaking dell'intero ecosistema di action esistenti: sconsigliata.

#### F2 — `Context < Hash` è la radice di più bug: preferire la composizione (in una major)
- **Severità**: Medio — **Posizione**: `context.rb:3`
- Ereditare da Hash espone ~120 metodi non progettati (finding 2.9), rende necessari gli override fragili di `[]`/`fetch` (2.1, 2.2) e la collisione degli accessor (2.4). Una classe che *contiene* un hash e delega solo `[]`, `[]=`, `key?`, `keys`, `each`, `to_h` chiuderebbe strutturalmente quella famiglia di bug. **Breaking change** (chi usa `ctx.merge`, `ctx.slice`… oggi): da fare solo in una major, con changelog esplicito.

#### F3 — Superficie API: quattro modi di fallire, due modi di leggere l'esito
- **Severità**: Medio — vedi finding 2.7. In più: l'esito si legge sia da `ctx.success?/failure?/message/error_code` sia da `ctx.outcome` (Result esposto e perfino scrivibile, finding 2.10-d). Consolidare su una via primaria documentata.

#### F4 — Incapsulamento
- **Severità**: Basso — `Monad#==` legge `other.instance_variable_get(:@value)` (`monad.rb:57`) perché `value` è privato nelle varianti Nullary. Con la migrazione a classi concrete (F4-Area 4) diventa un `protected attr_reader`. `WithCallback` usa la chiave "pubblica" `ctx[:callback]` come canale interno (`with_callback.rb:13`) con nesting max 2 dichiarato nel commento: da spostare su chiave riservata `:_callback` e da aggiungere alle reserved keys (finding 2.10-b).

---

### Area 6 — Modernizzazione e manutenibilità

#### F1 — Versione minima Ruby: 2.6 (EOL da marzo 2022)
- **Severità**: Medio — **Posizione**: `functional-light-service.gemspec:18`
- (Nota: la review precedente diceva ">= 2.5"; il valore reale è `>= 2.6.0`.) Il floor blocca `case/in` stabile (3.1), `Data.define` (3.2), e mantiene vivo codice di compatibilità. Proposta: **>= 3.1** (minimo per il refactor del match), meglio **>= 3.2** per `Data.define`. Breaking: major bump.

#### F2 — Copertura test: buona in superficie, cieca sui punti che contano
- **Severità**: Alto (è ciò che ha lasciato vivere il finding 1.1)
- **Posizione**: `spec/` (54 file)
- Comportamenti critici **non testati**, tutti dimostrati in questo audit:
  1. Seconda chiamata di un organizer con hook dichiarativi (`before_actions_spec.rb:54-58` chiama una sola volta) → finding 1.1.
  2. Qualunque scenario multi-thread (zero occorrenze di `Thread` in spec/).
  3. Contratto di `Context#fetch` (KeyError, no-write-on-read) → finding 2.1.
  4. Scrittura su chiave alias → finding 2.2.
  5. Rollback con action duplicate nella pipeline → finding 2.3.
  6. `skip_remaining!` dentro `iterate`/`reduce_if` e preservazione del messaggio → finding 2.5.
  7. Collisione `expects` con metodi Hash → finding 2.4.
- **Fix proposto**: aggiungere queste spec *prima* dei fix (red → green); sono la specifica del comportamento corretto.

#### F3 — README e documentazione
- **Severità**: Basso
- Residuo di fork non adattato: l'esempio di `fail_with_rollback!` usa `extend LightService::Action` (`README.md:814`) — copiandolo si ottiene `NameError`. Le occorrenze alle righe 134-202 sono narrativa storica sulla gem originale (accettabili, ma vale la pena etichettarle come tali). Mancano: la semantica per-scope di `skip_remaining!`, il contratto di non-condivisione del Context tra thread, la guida "quale fail usare quando".

#### F4 — Estensione nativa (Rust/C): non giustificata, con evidenza
- **Severità**: — (raccomandazione)
- I benchmark di quest'audit dimostrano che l'overhead è **CPU su reflection/eval Ruby evitabile in Ruby stesso**: il match engine perde 264x contro il `case/in` nativo *già disponibile nella VM*, e 17 dei 55 µs per call sono un deprecation-check rimuovibile. Dopo i fix 3.1-3.5 il profilo residuo è method dispatch che la VM esegue già in C. Un'estensione nativa per l'orchestrazione dovrebbe richiamare callback Ruby (le Action) attraverso il boundary nativo a ogni passo: si paga il crossing senza eliminare il costo dominante. **Quando avrebbe senso**: solo se dentro un'Action comparisse un algoritmo puro CPU-bound (parsing, hashing, calcolo numerico su grandi array) — e in quel caso **Rust + Magnus** (memory safety, build più gestibile per un singolo manutentore, precedenti reali: polars-rb, wasmtime-rb) e mai C (un errore di memoria = segfault del processo host). Percorso obbligato prima di qualunque nativo: profilare con `vernier`/`stackprof` un workload reale dopo i fix Ruby.

---

## 3. Piano di refactor prioritizzato

Ordine per (impatto × urgenza), con stima di impatto e rischio di regressione:

- [ ] **1. Scrivere le spec mancanti dei comportamenti rotti** (Area 6-F2: doppia chiamata con hook, fetch contract, alias write, rollback duplicati, skip in iterate). Impatto: alto (specifica del corretto). Rischio: nullo. *Da fare prima di ogni fix.*
- [ ] **2. Fix hook consumati da `with`** (finding 1.1) + redesign del meccanismo `ContextFactory`. Impatto: critico. Rischio: basso, circoscritto al testing helper.
- [ ] **3. Eliminare `@ctx` di classe e macro `ctx`** (1.2 / Area 4-F1). Impatto: chiude race + retention. Rischio: nullo (dead code).
- [ ] **4. Rimuovere `VerifyCallMethodExists`** (3.2 / Area 4-F2). Impatto: −17 µs/call, −30 righe. Rischio: quasi nullo (sparisce un warning deprecato).
- [ ] **5. Fix `Context#fetch`** (2.1): semantica Hash nativa. Impatto: contratto corretto. Rischio: medio — **breaking dichiarato** per chi si affida a `fetch(:x) ⇒ nil`.
- [ ] **6. Simmetria alias in `[]=` + inverse hash precomputato + bypass senza alias** (2.2, 3.4). Impatto: correttezza + 3x su ogni lettura. Rischio: basso.
- [ ] **7. Fix rollback con indice tracciato nel reduce** (2.3). Impatto: correttezza delle compensazioni. Rischio: basso.
- [ ] **8. `fail!` senza mutazione dell'input; reset dello skip separato dall'outcome; raise su collisione accessor** (2.6, 2.5, 2.4). Impatto: medio. Rischio: basso.
- [ ] **9. Riscrivere le operazioni Option/Result senza match engine; `match` come facciata su `case/in`** (3.1 / Area 4-F4). Impatto: fino a ~260x sugli hot path FP, −200 righe. Rischio: medio — coperto da enum/option/result spec. Richiede bump Ruby ≥ 3.1/3.2 (major).
- [ ] **10. Alleggerire `iterate`/`scoped_reduce` + handler no-op costante + inflector fuori dalla lambda** (3.5, 3.6-parte). Impatto: taglia gran parte dei ~55 µs/call nei loop. Rischio: basso. *Rimisurare con `bench.rb` dopo.*
- [ ] **11. Accessor per-classe-Action invece che per-istanza-context** (3.3). Impatto: ~5x sul setup per action. Rischio: medio (interazione con 2.4).
- [ ] **12. `frozen_string_literal` ovunque + gemspec pulito (dipendenze duplicate, `test_files`) + README (riga 814, doc semantiche mancanti)** (3.6, Area 4-F5, Area 6-F3). Impatto: igiene. Rischio: nullo.
- [ ] **13. Major release**: bump Ruby ≥ 3.1/3.2, deprecare `Maybe`/`Null` e gli operatori esotici, unificare l'API di fallimento, valutare Context per composizione (Area 5-F2). Impatto: manutenibilità a lungo termine. Rischio: alto ma dichiarato — è il punto dove i breaking change si concentrano deliberatamente.
- [ ] **14. Solo dopo tutto ciò**: profilare un workload reale con `vernier`; YJIT in produzione Linux; nativo (Rust+Magnus) solo se emerge un algoritmo puro CPU-bound — improbabile (Area 6-F4).

---

## 4. Cosa NON toccare

- **Il metodo Organizer / Action / Context con `expects`/`promises`**: la scomposizione in action piccole a singola responsabilità, la lista `actions` come documentazione vivente del flusso e la verifica dichiarativa delle chiavi sono il valore della libreria. Nessun finding li mette in discussione.
- **La verifica delle chiavi (`KeyVerifier`)**: design pulito (template method, tre verifier), costo proporzionato. Da estendere (reserved keys), non da riscrivere.
- **Il pattern decorator per il logging** (`WithReducerFactory` + `WithReducerLogDecorator`): separazione corretta, stato per-istanza (quindi per-chiamata), zero costo quando il logger è nullo.
- **`Result#map`/`bind` (il nucleo monadico senza match)**: misurato a solo 1,8x dal codice diretto — è la parte *sana* del layer funzionale. La riscrittura del match engine deve preservarne la semantica, non sostituirla.
- **La semantica di corto-circuito su failure** (`stop_processing?` controllato da ogni step): semplice, uniforme in tutti i costrutti (`execute`, `iterate`, `reduce_if`, `reduce_until`, `with_callback`), facile da ragionare.
- **`catch(:jump_when_failed)` come meccanismo interno** di `fail_and_return!`: è il male minore (le eccezioni per il flusso ordinario costerebbero di più); va incapsulato e documentato, non eliminato.
- **Il testing helper `ContextFactory` come concetto**: preparare un context reale eseguendo la pipeline fino all'action da testare è un'ottima idea; è solo il suo *meccanismo* (mutazione della classe organizer) a dover cambiare.

---

## Appendice — Riproducibilità

- Scenari di fallimento: script `audit/verify_findings.rb` (13 check, 12 confermati; l'unico non riprodotto — "fetch con default sovrascrive valori falsy" — è documentato come tale nel finding 2.1). Esecuzione: `ruby audit/verify_findings.rb` dalla root del progetto (richiede dry-inflector e i18n).
- Benchmark: script `audit/bench.rb` con `benchmark-ips`, 7 confronti; numeri riportati nei finding 3.1-3.5.
- Ambiente: Ruby 3.4.9 (x64-mingw-ucrt, senza YJIT), Windows 11; dipendenze runtime reali della gem (dry-inflector, i18n).
