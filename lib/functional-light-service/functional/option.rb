module FunctionalLightService
  Option = FunctionalLightService.enum do
    Some(:s)
    None()
  end

  class Option
    class << self
      def some?(expr)
        to_option(expr) { expr.nil? }
      end

      def any?(expr)
        to_option(expr) { expr.nil? || (expr.respond_to?(:empty?) && expr.empty?) }
      end

      def to_option(expr)
        yield(expr) ? None.new : Some.new(expr)
      end

      def try!
        yield
      rescue StandardError
        None.new
      end
    end
  end

  # rubocop:disable Metrics/BlockLength
  impl(Option) do
    class NoneValueError < StandardError; end

    def fmap
      match do
        Some() { |s| self.class.new(yield(s)) }
        None() { self }
      end
    end

    def map(&fn)
      match do
        Some() { |_s| bind(&fn) }
        None() { self }
      end
    end

    def some?
      is_a? Option::Some
    end

    def none?
      is_a? Option::None
    end

    alias :empty? :none?

    def value_or(n)
      match do
        Some() { |s| s }
        None() { n }
      end
    end

    def value_to_a
      @value
    end

    def +(other)
      match do
        None() { other }
        Some(where { !other.is_a?(Option) }) { |_| raise TypeError, "Other must be an #{Option}" }
        Some(where { other.some? }) { |s| Option::Some.new(s + other.value) }
        Some() { |_| self }
      end
    end
  end
  # rubocop:enable Metrics/BlockLength

  module Prelude
    module Option
      None = FunctionalLightService::Option::None.new
      Option = FunctionalLightService::Option
      # rubocop:disable Naming/MethodName
      def Some(s)
        FunctionalLightService::Option::Some.new(s)
      end

      def None
        FunctionalLightService::Prelude::Option::None
      end

      def Option
        FunctionalLightService::Option
      end
      # rubocop:enable Naming/MethodName
      # include Option
    end
  end
end
