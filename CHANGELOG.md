## 0.5.2 (2022-01-30)
### Fixed
-  Risoltro problema codecov upload perche non avevo settato il token ( 2025-05-16 ) [ sphynx79]


## 0.5.1 (2022-01-30)
### Removed
-  Rimuove supporto Travis CI, migrazione completa a GitHub Actions ( 2025-05-16 ) [ sphynx79]

## 0.5.0 (2022-01-30)
### GitHub
-  Aggiunto variabile RUN_COVERAGE_REPORT per eseguire il coverage solo nelle azioni di github  ( 2022-01-30 ) [ sphynx79]

### Github
-  Aggiornato il sistema per fare l'upload del coverage in https://docs.codecov.com/ nelle action di github  ( 2022-01-30 ) [ sphynx79]

### Test
-  organized_by with TestReduceIf organizer  ( 2022-01-30 ) [ sphynx79]
-  amend expectation titles to be clearer  ( 2022-01-30 ) [ sphynx79]
-  ensure that ctx.organized_by returns correct values  ( 2022-01-30 ) [ sphynx79]

### Style
-  sistemato per rubocop 2 allinemaenti parametri keyword  ( 2022-01-30 ) [ sphynx79]

### Doc
-  update README with notes about organized_by re: rollback  ( 2022-01-30 ) [ sphynx79]

### Added
-  ensure organized_by attr is set on context when Organizer is used  ( 2022-01-30 ) [ sphynx79]
-  add `Context#organized_by` attr  ( 2022-01-30 ) [ sphynx79]



## 0.4.9 (2022-01-30)
### Added
-  Agginyo altri test per #add_to_context e #add_aliases e inserito nel README l'utilizzo di add_to_context  ( 2022-01-30 ) [ sphynx79]

### Changed
-  migliorato spec per #add_aliases method  ( 2022-01-30 ) [ sphynx79]
-  migliorato la descrizione per spec add add_to_context method  ( 2022-01-30 ) [ sphynx79]



## 0.4.8 (2022-01-30)
### Added
-  Aggiuhnto il supporto per add_to_context and add_aliases organizer methods  ( 2022-01-30 ) [ sphynx79]



## 0.4.7 (2022-01-29)
### Fixed
-  sistemato il problema di rspec che mi dava un errore su un test ho dovuto fissare rspec-mocks alla versione 3.10.2 la 3.10.3 mi dava problemi  ( 2022-01-29 ) [ sphynx79]



## 0.4.6 (2022-01-29)
### Fixed
-  sistemato problema github action non trovava i gemfile rinominati  ( 2022-01-29 ) [ sphynx79]



## 0.4.5 (2022-01-29)
### Fixed
-  corretto il problema di spec che non passava i test option_spec match  ( 2022-01-29 ) [ sphynx79]
-   Aggiornato Appraisals per eseguire i test rspec e rubocop con diverse versione di i18n e dry_inflector  ( 2022-01-28 ) [ sphynx79]
-  Fix the spec description, order <=200 should not have free shipping  ( 2022-01-27 ) [ sphynx79]



## 0.4.4 (2022-01-27)
### Updated
-  Aggiornato la versione è sistemato problema upload codeconv  ( 2022-01-27 ) [ sphynx79]



## 0.4.3 (2022-01-27)
### Added
-  Aggiunto lo stato di codecov nel file readme  ( 2022-01-27 ) [ sphynx79]



## 0.4.2 (2022-01-27)
### Fixed
-  sistemato il path dove codeconv cerca il file del coverage  ( 2022-01-27 ) [ sphynx79]



## 0.4.1 (2022-01-27)
### Added
-  aggiunto supporto per codecov.com  ( 2022-01-27 ) [ sphynx79]



## 0.4.0 (2022-01-27)
### Aupdated
-  Aggioranto il readme, invece di travis uso il simbolo di github actions per vedere se tutti i test hanno dato esito positivo (rubocop,rspec)  ( 2022-01-27 ) [ sphynx79]



## 0.3.9 (2022-01-26)


## 0.3.8 (2022-01-26)
### Added
-  Aggiunto actions per fare i test in github  ( 2022-01-26 ) [ sphynx79]



## 0.3.7 (2022-01-26)


## 0.3.6 (2022-01-26)


## 0.3.5 (2022-01-26)


## 0.3.4 (2021-12-15)


## 0.3.3 (2021-12-15)
### Fixed
-  Corretto il problema di passare un hash per avere il dettaglio dell'errore quando fallisce  ( 2021-12-15 ) [ sphynx]



## 0.3.2 (2020-07-17)
### Changed
-  Ottimizzato performance di Deterministic [enum,result]  ( 2020-07-17 ) [ sphynx79]



## 0.3.1 (2020-02-16)


## 0.3.0 (2020-02-16)
### Removed
-  Rimosso completamente activesupport  ( 2020-02-16 ) [ sphynx79]



## 0.2.9.2 (2020-02-16)
### Removed
-  Rimosso ActiveSupport::Deprecation per i warning di deprecation  ( 2020-02-16 ) [ sphynx79]



## 0.2.9.1 (2020-02-16)
### Fixed
-  Sto cercando di sistemate il problema di travis che da errore per activesupport  ( 2020-02-16 ) [ sphynx79]



## 0.2.9 (2020-02-16)
### Fixed
-  Travis va in errore aggiunt activesupport al mio gemfile  ( 2020-02-16 ) [ sphynx79]



## 0.2.8 (2020-02-16)
### Removed
-  rimosso supporto a activesupport 5  ( 2020-02-16 ) [ sphynx79]



## 0.2.7 (2020-02-16)
### Fix
-  Risolto problema travis bundle update  ( 2020-02-16 ) [ sphynx79]



## 0.2.6 (2020-02-16)
### Fixed
-  FiFix problem /dev/null windows, e corretto il bug sul metodo failure?  ( 2020-02-16 ) [ sphynx79]



## 0.2.5 (2019-02-24)


## 0.2.4 (2019-02-24)


## 0.2.3 (2019-02-24)
### Added
-  test for null and option  ( 2019-02-24 ) [ sphynx79]



## 0.2.2 (2019-02-24)
### Added
-  make readme + some fix  ( 2019-02-24 ) [ sphynx79]



## 0.2.1 (2019-02-17)


## 0.2.1 (2019-02-17)
### Fixed
-  remove doble version in changelog  ( 2019-02-17 ) [ sphynx79]

### Removed
-  remove all orchestrator reference  ( 2019-02-17 ) [ sphynx79]

### Changed
-  cambiato versione parto dalla 0.1.0  ( 2019-02-17 ) [ sphynx79]



## 0.2.0 (2019-02-17)
### Removed
-  remove all orchestrator reference  ( 2019-02-17 ) [ sphynx79]

## 0.1.0 (2019-02-17)
### Changed
-  fork light-service gem and create first commmit  ( 2019-02-17 ) [ sphynx79]
