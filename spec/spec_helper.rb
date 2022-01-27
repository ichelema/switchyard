$LOAD_PATH << File.join(File.dirname(__FILE__), '..', 'lib')
$LOAD_PATH << File.join(File.dirname(__FILE__))

require 'simplecov'

SimpleCov.start do
  add_filter 'vendor/'
  add_filter %r{^/spec/}
end

SimpleCov.minimum_coverage_by_file 90

require 'simplecov-cobertura'
SimpleCov.formatter = SimpleCov::Formatter::CoberturaFormatter

require 'functional-light-service'
require 'functional-light-service/testing'
require "functional-light-service/functional/null"
require 'support'
require 'test_doubles'
require 'stringio'
