# Verifica dei finding dell'audit — eseguito contro lib/ reale
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require 'functional-light-service'

results = []
def check(results, name)
  ok, detail = yield
  results << [name, ok, detail]
rescue => e
  results << [name, :exception, "#{e.class}: #{e.message}"]
end

# ---------- F1: before_actions perso alla seconda chiamata ----------
class AddOne
  extend FunctionalLightService::Action
  expects :number
  promises :number
  executed { |ctx| ctx.number = ctx.number + 1 }
end

class Org1
  extend FunctionalLightService::Organizer
  before_actions ->(ctx) { ctx.number -= 10 if ctx.current_action == AddOne }
  def self.call(number)
    with(:number => number).reduce([AddOne])
  end
end

check(results, "F1 before_actions perso alla 2a chiamata") do
  r1 = Org1.call(0).fetch(:number)   # atteso: -10 + 1 = -9
  r2 = Org1.call(0).fetch(:number)   # se bug: hook perso -> 1
  [r1 == -9 && r2 == 1, "prima call=#{r1}, seconda call=#{r2}"]
end

# ---------- F2: Context#fetch — nessun KeyError e scrittura su read ----------
check(results, "F2a fetch(:missing) ritorna nil invece di KeyError e scrive la chiave") do
  ctx = FunctionalLightService::Context.make({})
  v = ctx.fetch(:missing)
  [v.nil? && ctx.to_h.key?(:missing), "valore=#{v.inspect}, chiavi dopo fetch=#{ctx.keys.inspect}"]
end

check(results, "F2b fetch con default sovrascrive un valore falsy esistente") do
  ctx = FunctionalLightService::Context.make(:flag => false)
  v = ctx.fetch(:flag, true)
  [v == true && ctx[:flag] == true, "fetch(:flag, true)=#{v.inspect}, ctx[:flag] ora=#{ctx[:flag].inspect} (era false)"]
end

# ---------- F3: alias asimmetrico lettura/scrittura ----------
check(results, "F3 scrittura su alias persa in lettura") do
  ctx = FunctionalLightService::Context.make(:codice_fiscale => "ABC")
  ctx.assign_aliases(:codice_fiscale => :cf)
  ctx[:cf] = "NUOVO"          # scrive la chiave :cf direttamente
  read = ctx[:cf]              # legge tradotto -> :codice_fiscale -> "ABC"
  [read == "ABC", "dopo ctx[:cf]='NUOVO', ctx[:cf]=#{read.inspect}; hash=#{ctx.to_h.inspect}"]
end

# ---------- F4: accessor non definito per chiavi che collidono con metodi Hash ----------
class UsesSize
  extend FunctionalLightService::Action
  expects :size
  executed { |ctx| ctx[:observed] = ctx.size }  # l'utente si aspetta il valore di :size
end

check(results, "F4 expects :size -> accessor non definito, ritorna Hash#size") do
  result = UsesSize.execute(:size => 999)
  [result[:observed] != 999, "ctx.size dentro l'action=#{result[:observed].inspect} (atteso dal punto di vista utente: 999)"]
end

# ---------- F5: @ctx a livello di classe Action (retention + race) ----------
check(results, "F5 la classe Action trattiene l'ultimo context in @ctx") do
  AddOne.execute(:number => 5)
  held = AddOne.instance_variable_get(:@ctx)
  [held.is_a?(FunctionalLightService::Context), "AddOne @ctx = #{held.inspect[0,80]}"]
end

# ---------- F6: fail! muta l'hash di opzioni del chiamante ----------
check(results, "F6 fail! cancella :error_code dall'hash del chiamante") do
  ctx = FunctionalLightService::Context.make({})
  opts = { :error_code => 500 }
  ctx.fail!("boom", opts)
  [!opts.key?(:error_code), "opts dopo fail! = #{opts.inspect}"]
end

# ---------- F7: Null#respond_to? con firma sbagliata ----------
check(results, "F7 Null#respond_to?(m, true) solleva ArgumentError") do
  begin
    Null.instance.respond_to?(:foo, true)
    [false, "nessuna eccezione"]
  rescue ArgumentError => e
    [true, "ArgumentError: #{e.message}"]
  end
end

# ---------- F8: Context#[] con aliases usa Hash#key (reverse lookup O(n)) ----------
check(results, "F8 lettura di chiave originale con molti alias resta corretta (sanity)") do
  ctx = FunctionalLightService::Context.make(:a => 1)
  ctx.assign_aliases(:a => :b)
  [ctx[:b] == 1 && ctx[:a] == 1, "ctx[:a]=#{ctx[:a]}, ctx[:b]=#{ctx[:b]}"]
end

# ---------- F9: skip_remaining! dentro iterate viene resettato ad ogni item ----------
class SkipAll
  extend FunctionalLightService::Action
  executed { |ctx| ctx.skip_remaining!("basta") if ctx[:counter] == 2 }
end
class CollectAction
  extend FunctionalLightService::Action
  executed { |ctx| (ctx[:seen] ||= []) << ctx[:counter] }
end
class OrgIter
  extend FunctionalLightService::Organizer
  def self.call(ctx)
    with(ctx).reduce([iterate(:counters, [SkipAll, CollectAction])])
  end
end

check(results, "F9 skip_remaining! dentro iterate NON ferma l'iterazione") do
  r = OrgIter.call(:counters => [1, 2, 3])
  [r[:seen] == [1, 3], "seen=#{r[:seen].inspect} (2 saltato, ma 3 processato: lo skip e' stato resettato)"]
end

# ---------- F10: succeed! + message perso da reset_skip_remaining! in scoped_reduce ----------
check(results, "F10 reset_skip_remaining! azzera anche message/outcome") do
  ctx = FunctionalLightService::Context.make({})
  ctx.succeed!("fatto bene")
  ctx.reset_skip_remaining!
  [ctx.message == '', "message dopo reset=#{ctx.message.inspect}"]
end

# ---------- F11: Context#select/map degradano a Hash ----------
check(results, "F11 Context#select ritorna Hash, non Context (perde outcome)") do
  ctx = FunctionalLightService::Context.make(:a => 1)
  sel = ctx.select { |_k, _v| true }
  [!sel.is_a?(FunctionalLightService::Context), "select.class=#{sel.class}"]
end

# ---------- F12: Some(nil) e' costruibile ----------
check(results, "F12 Some(nil) e' consentito (Option non valida il nil)") do
  s = FunctionalLightService::Option::Some.new(nil)
  [s.some? && s.value.nil?, "Some(nil).some?=#{s.some?}, value=nil"]
end

# ---------- F13: rollback con azione duplicata nella lista ----------
class RollA
  extend FunctionalLightService::Action
  executed { |ctx| (ctx[:trace] ||= []) << :a }
  rolled_back { |ctx| (ctx[:rb] ||= []) << :a }
end
class RollB
  extend FunctionalLightService::Action
  executed { |ctx| (ctx[:trace] ||= []) << :b; ctx.fail_with_rollback!("ko") if ctx[:trace].count(:b) == 2 }
  rolled_back { |ctx| (ctx[:rb] ||= []) << :b }
end
class OrgRoll
  extend FunctionalLightService::Organizer
  def self.call(ctx)
    with(ctx).reduce([RollB, RollA, RollB])   # RollB duplicata; fallisce la SECONDA RollB
  end
end

check(results, "F13 rollback con azione duplicata: index trova la 1a occorrenza -> rollback parziale") do
  r = OrgRoll.call({})
  # eseguite: B, A, B(fail). Rollback atteso: B, A, B. Con il bug: index(RollB)=0 -> solo [RollB].take(1) -> rollback solo B
  [r[:rb] == [:b], "trace=#{r[:trace].inspect}, rollback eseguiti=#{r[:rb].inspect} (attesi: [:b, :a, :b])"]
end

puts
results.each do |name, ok, detail|
  status = ok == true ? "CONFERMATO" : (ok == :exception ? "ECCEZIONE " : "NON RIPRODOTTO")
  puts "[#{status}] #{name}"
  puts "             -> #{detail}"
end
