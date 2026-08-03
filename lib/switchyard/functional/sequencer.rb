# frozen_string_literal: true

require 'delegate'

module Switchyard
  # Do-notation for {Result}: chains steps that return `Success`/`Failure`,
  # short-circuiting on the first `Failure`.
  #
  # Ported from the deterministic gem (MIT License, Copyright (c) Piotr
  # Zolnierek and contributors, https://github.com/pzol/deterministic).
  #
  # @example
  #   in_sequence do
  #     get(:user)  { fetch_user(id) }      # binds the Success value to :user
  #     let(:name)  { user.fetch(:name) }   # binds a plain (non-Result) value
  #     and_then    { validate(user) }      # step without binding
  #     observe     { log(name) }           # side effect, return value ignored
  #     and_yield   { Success(name) }       # final result of the sequence
  #   end
  #
  # @see Sequencer::Sequencer
  module Sequencer
    # Raised when sequence operations are used incorrectly.
    class InvalidSequenceError < StandardError; end

    # Struct-based operation descriptors for the sequence DSL.
    module Operation
      # Binds a {Result}'s value to a named variable.
      Get = Struct.new(:block, :name)

      # Binds a plain (non-Result) value to a named variable.
      Let = Struct.new(:block, :name)

      # Runs a step without binding its return value.
      AndThen = Struct.new(:block)

      # Runs a side-effect step whose return value is ignored.
      Observe = Struct.new(:block)

      # Final step that determines the sequence's return value.
      AndYield = Struct.new(:block)
    end

    # Enters the do-notation block to define a sequence.
    #
    # @yield block defining the steps (see {Sequencer::Sequencer})
    # @return [Result::Success, Result::Failure] the result of `and_yield`
    def in_sequence(&)
      sequencer = Sequencer.new(self)
      sequencer.instance_eval(&)
      sequencer.yield
    end

    # Internal sequencer that collects operations and compiles them into
    # a single pipeline.
    class Sequencer
      # @param instance [Object] the receiver for DSL blocks
      def initialize(instance)
        @operations = []
        @operation_wrapper = OperationWrapper.new(instance)
      end

      # Binds the {Result::Success Success} value of a block to a named variable.
      #
      # The block must return a {Result}. Its inner value is stored so
      # subsequent steps can reference it by name.
      #
      # @param name [Symbol] variable name
      # @yield must return a {Result}
      def get(name, &block)
        raise ArgumentError, 'no block given' unless block_given?
        raise InvalidSequenceError, 'and_yield already called' if @sequenced_operations

        @operations << Operation::Get.new(block, name)
      end

      # Binds a plain (non-Result) value to a named variable.
      #
      # @param name [Symbol] variable name
      # @yield return value is bound directly (no unwrapping)
      def let(name, &block)
        raise ArgumentError, 'no block given' unless block_given?
        raise InvalidSequenceError, 'and_yield already called' if @sequenced_operations

        @operations << Operation::Let.new(block, name)
      end

      # Adds a step without binding its result.
      #
      # The block must return a {Result}; its value is discarded.
      #
      # @yield must return a {Result}
      def and_then(&block)
        raise ArgumentError, 'no block given' unless block_given?
        raise InvalidSequenceError, 'and_yield already called' if @sequenced_operations

        @operations << Operation::AndThen.new(block)
      end

      # Adds a side-effect step whose return value is ignored.
      #
      # @yield the side effect
      def observe(&block)
        raise ArgumentError, 'no block given' unless block_given?
        raise InvalidSequenceError, 'and_yield already called' if @sequenced_operations

        @operations << Operation::Observe.new(block)
      end

      # Finalises the sequence and provides the return value.
      #
      # Must be called as the last step.
      #
      # @yield return value becomes the result of the whole sequence
      def and_yield(&block)
        raise ArgumentError, 'no block given' unless block_given?
        raise InvalidSequenceError, 'and_yield already called' if @sequenced_operations

        @operations << Operation::AndYield.new(block)

        prepare_sequenced_operations
      end

      # Executes the compiled sequence.
      #
      # @return [Result] the result of `and_yield`
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

    # Delegates method calls to the wrapped instance, checking bound
    # sequence variables first.
    #
    # When a method name matches a variable bound via `get` or `let`,
    # the stored value is returned directly instead of forwarding to
    # the wrapped instance.
    class OperationWrapper < SimpleDelegator
      # @param args forwarded to `SimpleDelegator`
      def initialize(*args)
        super
        @gotten_results = {}
      end

      # Resolves method calls against bound sequence variables.
      #
      # @param name [Symbol] method name
      # @param args [Array] positional arguments
      # @param kwargs [Hash] keyword arguments
      # @yield block argument
      # @return [Object] the bound value or delegated result
      def method_missing(name, *args, **kwargs, &)
        if @gotten_results.key?(name)
          @gotten_results[name]
        else
          super
        end
      end

      # @param name [Symbol]
      # @param include_private [Boolean]
      # @return [Boolean]
      def respond_to_missing?(name, include_private = false)
        @gotten_results.key?(name) || super
      end
    end
  end

  module Prelude
    include Sequencer
  end
end
