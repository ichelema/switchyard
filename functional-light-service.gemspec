require File.expand_path('../lib/functional-light-service/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Boscolo Michele"]
  gem.email         = ["miboscol@gmail.com"]
  gem.description   = %q{FunctionalLightService combines the Organizer/Action/Context pattern of LightService with functional programming constructs (Result/Option monads, pattern matching) inspired by Deterministic: complex workflows are organized into small single-purpose actions with functional error handling.}
  gem.summary       = %q{A service skeleton with an emphasis on simplicity with a pinch a functional programming}
  gem.homepage      = "https://github.com/sphynx79/functional-light-service"
  gem.license       = "MIT"

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.name          = "functional-light-service"
  gem.require_paths = ["lib"]
  gem.version       = FunctionalLightService::VERSION
  gem.required_ruby_version = '>= 3.1.0'

  gem.add_runtime_dependency("dry-inflector", ">= 0.2.1", "< 2")
  gem.add_runtime_dependency("i18n", "~> 1.8", ">= 1.8.11")
  # logger non e' piu una default gem da Ruby 3.5/4.0: senza questa
  # dichiarazione `require 'logger'` fallisce sotto Bundler
  gem.add_runtime_dependency("logger", "~> 1.5")

  gem.add_development_dependency("rake", "~> 13.0")
  gem.add_development_dependency("rspec", "~> 3.13")
  gem.add_development_dependency("simplecov", "~> 0.22")
  gem.add_development_dependency("simplecov-cobertura", "~> 3.0")
  gem.add_development_dependency("rubocop", "~> 1.75")
  gem.add_development_dependency("rubocop-performance", "~> 1.20")
  gem.add_development_dependency("pry", "~> 0.15")
  gem.add_development_dependency("solargraph", "~> 0.50")
  gem.add_development_dependency("benchmark-ips", "~> 2.13")
end
