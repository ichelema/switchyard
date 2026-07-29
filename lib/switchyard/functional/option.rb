# frozen_string_literal: true

module Switchyard
  Option = Switchyard.enum do
    Some(:s)
    None()
  end

  class Option
    class Some
      def initialize(init)
        raise ArgumentError, "Some cannot wrap nil: use None instead" if init.nil?

        super
      end
    end

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

  # Le operazioni usano il dispatch diretto invece del motore match:
  # stessa semantica, ~2 ordini di grandezza piu veloce (audit, finding 3.1)
  impl(Option) do
    def fmap
      some? ? self.class.new(yield(@value)) : self
    end

    def map(&fn)
      some? ? bind(&fn) : self
    end

    def some?
      is_a? Option::Some
    end

    def none?
      is_a? Option::None
    end

    alias :empty? :none?

    def value_or(n)
      some? ? @value : n
    end

    def value_to_a
      @value
    end

    def +(other)
      Switchyard::Deprecations.warn(
        "Option#+ is deprecated and will be removed in a future release; " \
        "combine the two options explicitly"
      )
      return other if none?
      raise TypeError, "Other must be an #{Option}" unless other.is_a?(Option)

      other.some? ? Option::Some.new(@value + other.value) : self
    end
  end

  module Prelude
    module Option
      None = Switchyard::Option::None.new
      Option = Switchyard::Option
      # rubocop:disable Naming/MethodName
      def Some(s)
        Switchyard::Option::Some.new(s)
      end

      def None
        Switchyard::Prelude::Option::None
      end

      def Option
        Switchyard::Option
      end
      # rubocop:enable Naming/MethodName
      # include Option
    end
  end
end
