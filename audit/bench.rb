# Micro-benchmark dei costi nascosti individuati nell'audit
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require 'functional-light-service'
require 'benchmark/ips'

include FunctionalLightService::Prelude::Result
include FunctionalLightService::Prelude::Option

puts "Ruby #{RUBY_VERSION}, YJIT: #{defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled? ? 'on' : 'off'}"
puts

some = Some(42)
success = Success(42)

# 1) Costo del motore match (Option#value_or usa match) vs equivalente diretto
Benchmark.ips do |x|
  x.report("Option#value_or (match engine)") { some.value_or(0) }
  x.report("equivalente is_a? diretto")      { some.is_a?(FunctionalLightService::Option::Some) ? some.value : 0 }
  x.report("case/in nativo Ruby") do
    case some
    in FunctionalLightService::Option::Some then some.value
    else 0
    end
  end
  x.compare!
end

# 2) match esplicito con guard (Struct.new per chiamata) su Result#+
Benchmark.ips do |x|
  other = Success(1)
  x.report("Result#+ (match con guard -> Struct.new/call)") { success + other }
  x.report("somma diretta is_a?") do
    if success.is_a?(FunctionalLightService::Result::Success) && other.is_a?(FunctionalLightService::Result::Success)
      FunctionalLightService::Result::Success.new(success.value + other.value)
    end
  end
  x.compare!
end

# 3) Result#map (bind, senza match) — per confronto: la parte "sana"
Benchmark.ips do |x|
  f = ->(v) { Success(v + 1) }
  x.report("Result#map via bind") { success.map(f) }
  x.report("lambda diretta")      { success.is_a?(FunctionalLightService::Result::Success) ? f.call(success.value) : success }
  x.compare!
end

# 4) Overhead di Organizer.with: caller(1..1) + methods.include?(:call)
Benchmark.ips do |x|
  klass = Class.new { def self.call; end }
  x.report("caller(1..1) + methods.include?") do
    c = caller(1..1).first
    c =~ /`(.*)'/
    klass.methods.include?(:call)
  end
  x.report("respond_to?(:call) soltanto") { klass.respond_to?(:call) }
  x.compare!
end

# 5) define_accessor_methods_for_keys: singleton methods per ogni context
Benchmark.ips do |x|
  keys = %i[number total counter]
  x.report("nuovo Context + define accessor per keys") do
    ctx = FunctionalLightService::Context.make(:number => 1, :total => 2, :counter => 3)
    ctx.define_accessor_methods_for_keys(keys)
  end
  x.report("nuovo Context senza accessor") do
    FunctionalLightService::Context.make(:number => 1, :total => 2, :counter => 3)
  end
  x.compare!
end

# 6) Context#[] con alias attivi (Hash#key reverse scan) vs Hash puro
Benchmark.ips do |x|
  ctx = FunctionalLightService::Context.make(:a => 1, :b => 2, :c => 3)
  ctx.assign_aliases(:a => :alfa)
  h = { :a => 1, :b => 2, :c => 3 }
  x.report("Context#[] (con lookup alias)") { ctx[:b] }
  x.report("Hash#[] puro")                  { h[:b] }
  x.compare!
end

# 7) Organizer end-to-end: quota di overhead per call minimale
class BenchAdd
  extend FunctionalLightService::Action
  expects :number
  executed { |ctx| ctx[:number] = ctx[:number] + 1 }
end
class BenchOrg
  extend FunctionalLightService::Organizer
  def self.call(n)
    with(:number => n).reduce([BenchAdd])
  end
end
Benchmark.ips do |x|
  x.report("Organizer.call 1 action") { BenchOrg.call(1) }
  x.report("lavoro utile equivalente") { { :number => 1 }.tap { |h| h[:number] += 1 } }
  x.compare!
end
