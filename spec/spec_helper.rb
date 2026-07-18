$LOAD_PATH << File.join(File.dirname(__FILE__), '..', 'lib')
$LOAD_PATH << File.join(File.dirname(__FILE__))

if ENV['RUN_COVERAGE_REPORT']
  require 'simplecov'

  SimpleCov.start do
    add_filter 'vendor/'
    add_filter %r{^/spec/}
  end

  SimpleCov.minimum_coverage 98
  SimpleCov.minimum_coverage_by_file 90

  require "simplecov-cobertura"
  SimpleCov.formatter = SimpleCov::Formatter::CoberturaFormatter
end

# i18n non e' piu una dipendenza runtime della gem: viene caricata qui
# per testare l'adapter I18n e la selezione automatica in Configuration
require "i18n"
require "functional-light-service"
require "functional-light-service/testing"
require "functional-light-service/functional/null"
require "support"
require "test_doubles"
require "stringio"

# Le API deprecate (Maybe/Null, operatori esotici) restano testate:
# i warning vengono silenziati globalmente e riattivati solo nelle
# spec che li verificano
FunctionalLightService::Deprecations.silenced = true
