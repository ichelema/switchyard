# frozen_string_literal: true

module Switchyard
  # Base monad behaviour shared by {Option} and {Result}.
  #
  # Provides `fmap` (functor), `bind` (monadic bind), value extraction
  # and equality comparison.
  #
  # @abstract Include in your own monad implementations.
  #
  # @example
  #   class MyMonad
  #     include Switchyard::Monad
  #   end
  #
  module Monad
    # Raised when a monad operation receives a value of the wrong type.
    class NotMonadError < StandardError; end

    # Wraps a value, avoiding double-wrapping (the `pure` operation).
    #
    # If `init` is already an instance of the same monad class, its inner
    # value is unwrapped first.
    #
    # @param init [Object] the value to wrap
    def initialize(init)
      @value = join(init)
    end

    # Unwraps a monad-wrapped value, returning its inner value directly.
    #
    # `M[M[A]]` is collapsed to `M[A]`.
    #
    # @param other [Object] the potential monad to unwrap
    # @return [Object] the unwrapped value
    def join(other)
      if other.is_a? self.class
        other.value
      else
        other
      end
    end

    # Functor map: applies a function to the inner value and wraps the
    # result back in the same monad.
    #
    # `fmap :: (a -> b) -> M a -> M b`
    #
    # @param proc [Proc, nil] a callable, or use the block form
    # @yield [value] transformation
    # @yieldparam value [Object] the inner value
    # @return [Monad] a new monad instance with the transformed value
    def fmap(proc = nil, &block)
      result = (proc || block).call(value)
      self.class.new(result)
    end

    # Monadic bind: applies a function that returns a monad.
    #
    # The function receives the inner value and **must** return an instance
    # of the same monad class. A {NotMonadError} is raised otherwise.
    #
    # `bind :: (a -> M b) -> M a -> M b`
    #
    # @param proc [Proc, nil] a callable, or use the block form
    # @yield [value] monad-returning function
    # @yieldparam value [Object] the inner value
    # @return [Monad] the monad returned by the function
    # @raise [NotMonadError] if the function does not return the correct type
    def bind(proc = nil, &block)
      (proc || block).call(value).tap do |result|
        # rubocop:disable Style/CaseEquality
        parent = self.class.superclass === Object ? self.class : self.class.superclass
        # rubocop:enable Style/CaseEquality
        unless result.is_a? parent
          raise NotMonadError, "Expected #{result.inspect} to be an #{parent}"
        end
      end
    end
    # rubocop:disable Naming/MethodName
    alias :'>>=' :bind
    # rubocop:enable Naming/MethodName

    # Unwraps and returns the inner value.
    #
    # @return [Object] the wrapped value
    def value
      @value
    end

    # Returns the string representation of the inner value.
    #
    # @return [String]
    def to_s
      value.to_s
    end

    # Two monads are equivalent when they are of the same type and their
    # values are equal.
    #
    # @param other [Object] the other instance
    # @return [Boolean]
    def ==(other)
      return false unless other.is_a? self.class

      @value == other.monad_value
    end

    # Protected reader for cross-instance equality comparison.
    #
    # `#value` is private in Nullary variants (e.g. `None`), so this
    # protected accessor lets same-type monads compare their values.
    #
    # @api private
    # @return [Object] the inner value
    def monad_value
      @value
    end
    protected :monad_value

    # Returns a human-readable representation of the monad.
    #
    # @example
    #   Success(42).inspect  # => "Success(42)"
    #
    # @return [String]
    def inspect
      pretty_class_name = self.class.name.split('::')[-1]
      "#{pretty_class_name}(#{value.inspect})"
    end
  end
end
