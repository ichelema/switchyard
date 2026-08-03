# frozen_string_literal: true

module Switchyard
  # The {Result} enum — the core monad for railway-oriented programming.
  #
  # A result is either a {Result::Success Success} wrapping a value, or a
  # {Result::Failure Failure} wrapping an error. Use `map`/`>>` to chain
  # operations that may fail; the first `Failure` short-circuits the chain.
  #
  # @example Basic usage
  #   result = Success(42) >> ->(v) { Success(v + 1) }
  #   result.value # => 43
  #
  # @example With failure
  #   result = Success(42) >> ->(_v) { Failure("oops") }
  #   result.failure? # => true
  #
  # @see Switchyard::Prelude::Result for the `Success()`/`Failure()` helpers
  #
  Result = Switchyard.enum do
    Success(:s)
    Failure(:f)
  end

  # Class-level helpers for {Result}.
  # @see Result for the enum definition and instance methods
  class Result
    class << self
      # Wraps a block's return value in a {Success}, or catches an
      # exception and wraps it in a {Failure}.
      #
      # @example
      #   Result.try! { risky_operation }
      #   # => Success(value) or Failure(exception)
      #
      # @yield the operation that may raise
      # @return [Success] on success
      # @return [Failure] on exception
      def try!
        Success.new(yield)
      rescue StandardError => e
        Failure.new(e)
      end
    end

    # The variants are generated at runtime by Switchyard.enum; they are
    # declared here via @!parse so YARD can see them during static analysis.
    # Names are fully qualified because YARD parses this block in the
    # Switchyard namespace, not in Result.
    # @!parse
    #   # The success variant, wrapping a value.
    #   class Result::Success < Result; end

    # @!parse
    #   # The failure variant, wrapping an error.
    #   class Result::Failure < Result; end
  end

  # rubocop:disable Metrics/BlockLength
  Switchyard.impl(Result) do
    # Chains a successful result through a monadic function.
    #
    # The block **must** return a {Result}. Short-circuits on failure.
    #
    # @example
    #   Success(1).map { |v| Success(v + 1) } # => Success(2)
    #   Failure(0).map { |v| Success(v + 1) } # => Failure(0)
    #
    # @param proc [Proc, nil] callable, or use block
    # @yield [value] the inner value on success
    # @return [Result] the result of the block (on success) or self (on failure)
    def map(proc = nil, &block)
      success? ? bind(proc || block) : self
    end

    alias :>> :map
    alias :and_then :map

    def map_err(proc = nil, &block)
      failure? ? bind(proc || block) : self
    end

    alias :or_else :map_err

    # Applies a side-effect proc and returns `self` unchanged.
    #
    # Use for logging, instrumentation, etc.
    #
    # @param proc [Proc, nil] callable that receives the result, or use block
    # @yield [self] the result
    # @return [self]
    def pipe(proc = nil, &block)
      (proc || block).call(self)
      self
    end

    # @deprecated Use {#pipe} instead.
    def <<(proc = nil, &block)
      Switchyard::Deprecations.warn(
        "Result#<< is deprecated; use #pipe instead"
      )
      pipe(proc, &block)
    end

    # Returns whether this result is a {Success}.
    #
    # @return [Boolean]
    def success?
      is_a? Result::Success
    end

    # Returns whether this result is a {Failure}.
    #
    # @return [Boolean]
    def failure?
      is_a? Result::Failure
    end

    # Returns `self` on success, `other` on failure (disjunction).
    #
    # @param other [Result]
    # @return [Result]
    def or(other)
      unless other.is_a? Result
        msg = "Expected #{other.inspect} to be a Result"
        raise Switchyard::Monad::NotMonadError, msg
      end

      success? ? self : other
    end

    # Returns `other` on success, `self` on failure (conjunction).
    #
    # @param other [Result]
    # @return [Result]
    def and(other)
      unless other.is_a? Result
        msg = "Expected #{other.inspect} to be a Result"
        raise Switchyard::Monad::NotMonadError, msg
      end

      success? ? other : self
    end

    # @deprecated Combine results explicitly instead.
    def +(other)
      Switchyard::Deprecations.warn(
        "Result#+ is deprecated and will be removed in a future release; " \
        "combine the two results explicitly"
      )
      unless other.is_a? Result
        msg = "Expected #{other.inspect} to be a Result"
        raise Switchyard::Monad::NotMonadError, msg
      end

      if success? == other.success?
        self.class.new(value + other.value)
      elsif success?
        other # other is the failure
      else
        self # self is the failure
      end
    end

    # Maps a function, rescuing exceptions into a {Failure}.
    #
    # @param proc [Proc, nil] callable, or use block
    # @yield [value] the inner value
    # @return [Result]
    def try(proc = nil, &block)
      map(proc, &block)
    rescue StandardError => e
      Result::Failure.new(e)
    end

    # @deprecated Use {#try} instead.
    def >=(proc = nil, &block)
      Switchyard::Deprecations.warn(
        "Result#>= is deprecated; use #try instead"
      )
      try(proc, &block)
    end
  end
  # rubocop:enable Metrics/BlockLength
end

module Switchyard
  # Convenience helpers that can be included anywhere.
  #
  # @!visibility public
  module Prelude
    # Helper methods for working with {Switchyard::Result results}.
    #
    # Include this module (or {Prelude} itself) to get `Success()`,
    # `Failure()` and `try!` as local methods.
    #
    # @example
    #   include Switchyard::Prelude::Result
    #   Success(42)  # => #<Success ...>
    #
    module Result
      # rubocop:disable Naming/MethodName
      # Wraps a block in a {Switchyard::Result.try!} call.
      #
      # @yield the operation
      # @return [Success, Failure]
      def try!(&)
        Switchyard::Result.try!(&)
      end

      # Creates a {Switchyard::Result::Success}.
      #
      # @param s [Object] the value
      # @return [Switchyard::Result::Success]
      def Success(s)
        Switchyard::Result::Success.new(s)
      end

      # Creates a {Switchyard::Result::Failure}.
      #
      # @param f [Object] the error
      # @return [Switchyard::Result::Failure]
      def Failure(f)
        Switchyard::Result::Failure.new(f)
      end
      # rubocop:enable Naming/MethodName
    end

    include Result
  end
end
