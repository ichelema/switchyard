# frozen_string_literal: true

module Switchyard
  # The {Option} enum — represents an optional value.
  #
  # An option is either {Option::Some Some} wrapping a value, or
  # {Option::None None} representing absence. Unlike {Result}, failure
  # carries no error information.
  #
  # @example
  #   Some(42).value_or(0)  # => 42
  #   None.value_or(0)      # => 0
  #
  # @see Switchyard::Option::Some
  # @see Switchyard::Option::None
  # @see Switchyard::Prelude::Option for the `Some()`/`None()` helpers
  #
  Option = Switchyard.enum do
    Some(:s)
    None()
  end

  # The {Option} enum class — represents an optional value.
  #
  # An option is either {Option::Some Some} wrapping a value, or
  # {Option::None None} representing absence. Unlike {Result}, failure
  # carries no error information.
  class Option
    # A value-bearing option variant.
    #
    # Raises `ArgumentError` when constructed with `nil` — use {None}
    # to represent absence.
    class Some
      # @param init [Object] the wrapped value
      # @raise [ArgumentError] if `init` is `nil`
      def initialize(init)
        raise ArgumentError, "Some cannot wrap nil: use None instead" if init.nil?

        super
      end
    end

    class << self
      # Converts a possibly-nil expression to {Some} or {None}.
      #
      # @example
      #   Option.some?(nil)      # => None
      #   Option.some?("hello")  # => Some("hello")
      #
      # @param expr [Object] the value to wrap
      # @return [Some] when expr is not nil
      # @return [None] when expr is nil
      def some?(expr)
        to_option(expr) { expr.nil? }
      end

      # Converts a value to {Some} or {None}, treating empty collections
      # as absent.
      #
      # @example
      #   Option.any?(nil)   # => None
      #   Option.any?([])    # => None
      #   Option.any?([1])   # => Some([1])
      #
      # @param expr [Object] the value to wrap
      # @return [Some] when truthy and non-empty
      # @return [None] when nil or empty
      def any?(expr)
        to_option(expr) { expr.nil? || (expr.respond_to?(:empty?) && expr.empty?) }
      end

      # Internal helper that yields the predicate and returns the
      # appropriate variant.
      #
      # @api private
      # @param expr [Object]
      # @yield predicate — returns truthy when `None` should be returned
      # @return [Some, None]
      def to_option(expr)
        yield(expr) ? None.new : Some.new(expr)
      end

      # Wraps a block in a {Some}/{None} — exceptions become {None}.
      #
      # @example
      #   Option.try! { 1 / 0 }  # => None
      #
      # @yield the operation
      # @return [Some] on success
      # @return [None] on exception
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
    # Functor map: transforms the inner value, rewrapping as an option.
    #
    # @example
    #   Some(1).fmap { |n| n + 1 }  # => Some(2)
    #   None.fmap { |n| n + 1 }     # => None
    #
    # @yield [value] transformation block
    # @return [Some, None]
    def fmap
      some? ? self.class.new(yield(@value)) : self
    end

    # Monadic bind: chains an option-returning function.
    #
    # @example
    #   Some(1).map { |n| Some(n + 1) }  # => Some(2)
    #   None.map { |n| Some(n + 1) }     # => None
    #
    # @yieldparam value [Object] the inner value
    # @yieldreturn [Some, None]
    # @return [Some, None]
    def map(&fn)
      some? ? bind(&fn) : self
    end

    # Returns whether this is a {Some}.
    #
    # @return [Boolean]
    def some?
      is_a? Option::Some
    end

    # Returns whether this is a {None}.
    #
    # @return [Boolean]
    def none?
      is_a? Option::None
    end

    alias :empty? :none?

    # Returns the value if present, or a fallback.
    #
    # @example
    #   Some(1).value_or(0)  # => 1
    #   None.value_or(0)     # => 0
    #
    # @param n [Object] fallback when {None}
    # @return [Object]
    def value_or(n)
      some? ? @value : n
    end

    # @deprecated Use explicit unwrapping instead.
    def value_to_a
      @value
    end

    # @deprecated Combine options explicitly instead.
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
    # Helper methods for working with {Switchyard::Option options}.
    #
    # Include this module to get `Some()`, `None()` and `Option()` as
    # local methods.
    #
    # @example
    #   include Switchyard::Prelude::Option
    #   Some(42)  # => #<Option::Some ...>
    #
    module Option
      # The shared {Switchyard::Option::None} instance.
      None = Switchyard::Option::None.new

      # Reference to {Switchyard::Option} for use in method bodies.
      Option = Switchyard::Option

      # rubocop:disable Naming/MethodName
      # Creates a {Switchyard::Option::Some}.
      #
      # @param s [Object] the value
      # @return [Switchyard::Option::Some]
      def Some(s)
        Switchyard::Option::Some.new(s)
      end

      # Returns the shared {Switchyard::Option::None} instance.
      #
      # @return [Switchyard::Option::None]
      def None
        Switchyard::Prelude::Option::None
      end

      # Returns the {Switchyard::Option} module.
      #
      # @return [Class] Switchyard::Option
      def Option
        Switchyard::Option
      end
      # rubocop:enable Naming/MethodName
    end
  end
end
