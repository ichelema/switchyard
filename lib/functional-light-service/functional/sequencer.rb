# frozen_string_literal: true

require 'delegate'

module FunctionalLightService
  # Do-notation for Result: chains steps that return Success/Failure,
  # short-circuiting on the first Failure. Ported from the deterministic
  # gem (MIT License, Copyright (c) Piotr Zolnierek and contributors,
  # https://github.com/pzol/deterministic).
  #
  #   in_sequence do
  #     get(:user)  { fetch_user(id) }      # binds the Success value to :user
  #     let(:name)  { user.fetch(:name) }   # binds a plain (non-Result) value
  #     and_then    { validate(user) }      # step without binding
  #     observe     { log(name) }           # side effect, return value ignored
  #     and_yield   { Success(name) }       # final result of the sequence
  #   end
  module Sequencer
    class InvalidSequenceError < StandardError; end

    module Operation
      Get = Struct.new(:block, :name)
      Let = Struct.new(:block, :name)
      AndThen = Struct.new(:block)
      Observe = Struct.new(:block)
      AndYield = Struct.new(:block)
    end

    def in_sequence(&)
      sequencer = Sequencer.new(self)
      sequencer.instance_eval(&)
      sequencer.yield
    end

    class Sequencer
      def initialize(instance)
        @operations = []
        @operation_wrapper = OperationWrapper.new(instance)
      end

      def get(name, &block)
        raise ArgumentError, 'no block given' unless block_given?
        raise InvalidSequenceError, 'and_yield already called' if @sequenced_operations

        @operations << Operation::Get.new(block, name)
      end

      def let(name, &block)
        raise ArgumentError, 'no block given' unless block_given?
        raise InvalidSequenceError, 'and_yield already called' if @sequenced_operations

        @operations << Operation::Let.new(block, name)
      end

      def and_then(&block)
        raise ArgumentError, 'no block given' unless block_given?
        raise InvalidSequenceError, 'and_yield already called' if @sequenced_operations

        @operations << Operation::AndThen.new(block)
      end

      def observe(&block)
        raise ArgumentError, 'no block given' unless block_given?
        raise InvalidSequenceError, 'and_yield already called' if @sequenced_operations

        @operations << Operation::Observe.new(block)
      end

      def and_yield(&block)
        raise ArgumentError, 'no block given' unless block_given?
        raise InvalidSequenceError, 'and_yield already called' if @sequenced_operations

        @operations << Operation::AndYield.new(block)

        prepare_sequenced_operations
      end

      def yield
        raise InvalidSequenceError, 'and_yield not called' unless @sequenced_operations

        @operation_wrapper.instance_eval(&@sequenced_operations)
      end

      private

      # rubocop:disable Metrics/MethodLength, Metrics/CyclomaticComplexity
      def prepare_sequenced_operations
        operations = @operations

        @sequenced_operations = ->(_) do
          operations.reduce(Result::Success.new(nil)) do |last_result, operation|
            last_result.map do
              case operation
              when Operation::Get
                result = instance_eval(&operation.block)
                result.map do |output|
                  # Runs in the context of the OperationWrapper, so the
                  # bound value is stored within the wrapper itself.
                  @gotten_results[operation.name] = output
                  result
                end
              when Operation::Let
                @gotten_results[operation.name] = instance_eval(&operation.block)
                last_result
              when Operation::Observe
                instance_eval(&operation.block)
                last_result
              when Operation::AndThen, Operation::AndYield
                instance_eval(&operation.block)
              end
            end
          end
        end
      end
      # rubocop:enable Metrics/MethodLength, Metrics/CyclomaticComplexity
    end

    # OperationWrapper proxies all method calls to the wrapped instance, but
    # first checks if the name of the called method matches a value stored
    # within @gotten_results and returns the value if it does.
    class OperationWrapper < SimpleDelegator
      def initialize(*args)
        super
        @gotten_results = {}
      end

      def method_missing(name, *args, **kwargs, &)
        if @gotten_results.key?(name)
          @gotten_results[name]
        else
          super
        end
      end

      def respond_to_missing?(name, include_private = false)
        @gotten_results.key?(name) || super
      end
    end
  end

  module Prelude
    include Sequencer
  end
end
