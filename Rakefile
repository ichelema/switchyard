require "bundler/gem_tasks"

require "rubygems"
require "bundler/setup"

require 'rspec/core/rake_task'
require 'rubocop/rake_task'
require 'yard'
require 'yard/rake/yardoc_task'

RuboCop::RakeTask.new
RSpec::Core::RakeTask.new(:spec)
YARD::Rake::YardocTask.new(:yard)

task(:default).clear
task :default => %i[spec rubocop]
