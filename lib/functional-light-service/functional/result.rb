module FunctionalLightService
  Result = FunctionalLightService.enum do
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
  FunctionalLightService.impl(Result) do
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

    alias :<< :pipe

    def success?
      is_a? Result::Success
    end

    def failure?
      is_a? Result::Failure
    end

    def or(other)
      unless other.is_a? Result
        msg = "Expected #{other.inspect} to be a Result"
        raise FunctionalLightService::Monad::NotMonadError, msg
      end

      match do
        Success() { |_| self }
        Failure() { |_| other }
      end
    end

    def and(other)
      unless other.is_a? Result
        msg = "Expected #{other.inspect} to be a Result"
        raise FunctionalLightService::Monad::NotMonadError, msg
      end

      match do
        Success() { |_| other }
        Failure() { |_| self }
      end
    end

    def +(other)
      unless other.is_a? Result
        msg = "Expected #{other.inspect} to be a Result"
        raise FunctionalLightService::Monad::NotMonadError, msg
      end

      match do
        Success(where { other.success? }) { |s| Result::Success.new(s + other.value) }
        Failure(where { other.failure? }) { |f| Result::Failure.new(f + other.value) }
        Success() { |_| other } # implied other.failure?
        Failure() { |_| self } # implied other.success?
      end
    end

    def try(proc = nil, &block)
      map(proc, &block)
    rescue StandardError => e
      Result::Failure.new(e)
    end

    alias :>= :try
  end
  # rubocop:enable Metrics/BlockLength
end

module FunctionalLightService
  module Prelude
    module Result
      # rubocop:disable Naming/MethodName
      def try!(&block)
        FunctionalLightService::Result.try!(&block)
      end

      def Success(s)
        FunctionalLightService::Result::Success.new(s)
      end

      def Failure(f)
        FunctionalLightService::Result::Failure.new(f)
      end
      # rubocop:enable Naming/MethodName
    end

    include Result
  end
end
