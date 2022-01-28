# -*- encoding: utf-8 -*-
require File.expand_path('../lib/functional-light-service/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Boscolo Michele"]
  gem.email         = ["miboscol@gmail.com"]
  gem.description   = %q{A service skeleton with an emphasis on simplicity with a pinch a functional programming}
  gem.summary       = %q{A service skeleton with an emphasis on simplicity with a pinch a functional programming}
  gem.homepage      = "https://github.com/sphynx79/functional-light-service"
  gem.license       = "MIT"

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "functional-light-service"
  gem.require_paths = ["lib"]
  gem.version       = FunctionalLightService::VERSION
  gem.required_ruby_version = '>= 2.6.0'

  gem.add_runtime_dependency("dry-inflector", "~> 0.2", ">= 0.2.1")
  gem.add_runtime_dependency("i18n", "~> 1.8", ">= 1.8.11")
  

  gem.add_development_dependency("i18n", "~> 1.8", ">= 1.8.11")
  gem.add_development_dependency("dry-inflector", "~> 0.2", ">= 0.2.1")
  gem.add_development_dependency("appraisal", "~> 2.4.1")
  gem.add_development_dependency("rspec", "~> 3.10.0")
  gem.add_development_dependency("simplecov", "~> 0.21.2")
  gem.add_development_dependency("simplecov-cobertura", "~> 2.1.0")
  gem.add_development_dependency("rubocop", "~> 1.25.0")
  gem.add_development_dependency("rubocop-performance", "~> 1.13.2")
  gem.add_development_dependency("pry", "~> 0.14.1")
  gem.add_development_dependency("solargraph", "~> 0.44.2")
  gem.add_development_dependency("nokogiri", "~> 1.12.5")
end
