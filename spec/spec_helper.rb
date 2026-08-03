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

# i18n is no longer a runtime dependency of the gem: it is loaded here to
# test the I18n adapter and the automatic selection in Configuration
require "i18n"
require "switchyard"
require "switchyard/testing"
require "switchyard/functional/null"
require "support"
require "test_doubles"
require "stringio"

# Deprecated APIs (Maybe/Null, exotic operators) remain under test:
# warnings are silenced globally and re-enabled only in the specs
# that verify them
Switchyard::Deprecations.silenced = true
