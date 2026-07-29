# frozen_string_literal: true

module Switchyard
  Result = Switchyard.enum do
    Success(:s)
    Failure(:f)
  end

  class Result
    class << self
      def try!
        Success.new(yield)
      rescue StandardError => e
        Failure.new(e)
      end
    end
  end

  # rubocop:disable Metrics/BlockLength
  Switchyard.impl(Result) do
    def map(proc = nil, &block)
      success? ? bind(proc || block) : self
    end

    alias :>> :map
    alias :and_then :map

    def map_err(proc = nil, &block)
      failure? ? bind(proc || block) : self
    end

    alias :or_else :map_err

    def pipe(proc = nil, &block)
      (proc || block).call(self)
      self
    end

    def <<(proc = nil, &block)
      Switchyard::Deprecations.warn(
        "Result#<< is deprecated; use #pipe instead"
      )
      pipe(proc, &block)
    end

    def success?
      is_a? Result::Success
    end

    def failure?
      is_a? Result::Failure
    end

    # Le operazioni usano il dispatch diretto invece del motore match:
    # stessa semantica, ~2 ordini di grandezza piu veloce (audit, finding 3.1)
    def or(other)
      unless other.is_a? Result
        msg = "Expected #{other.inspect} to be a Result"
        raise Switchyard::Monad::NotMonadError, msg
      end

      success? ? self : other
    end

    def and(other)
      unless other.is_a? Result
        msg = "Expected #{other.inspect} to be a Result"
        raise Switchyard::Monad::NotMonadError, msg
      end

      success? ? other : self
    end

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

    def try(proc = nil, &block)
      map(proc, &block)
    rescue StandardError => e
      Result::Failure.new(e)
    end

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
  module Prelude
    module Result
      # rubocop:disable Naming/MethodName
      def try!(&)
        Switchyard::Result.try!(&)
      end

      def Success(s)
        Switchyard::Result::Success.new(s)
      end

      def Failure(f)
        Switchyard::Result::Failure.new(f)
      end
      # rubocop:enable Naming/MethodName
    end

    include Result
  end
end
