# frozen_string_literal: true

module Switchyard
  module Organizer
    # Executes a pipeline of actions step by step, handling rollback and
    # optional around-each wrappers.
    #
    # Normally you obtain a reducer through {ClassMethods#with} and call
    # {#reduce} with the action list.
    #
    # @example
    #   WithReducer.new(MyOrganizer)
    #     .with(:number => 0)
    #     .reduce([AddOne, AddTwo, AddThree])
    #
    class WithReducer
      # @return [Context] the current context
      attr_reader :context

      # @return [Module, nil] the organizer that owns this reducer
      attr_accessor :organizer

      # @param monitored_organizer [Module, nil] the owning organizer
      def initialize(monitored_organizer = nil)
        @organizer = monitored_organizer
      end

      # Initialises the context and records the owning organizer.
      #
      # @param data [Hash, Context] initial data
      # @return [self]
      def with(data = {})
        @context = Switchyard::Context.make(data)
        @context.organized_by = organizer
        self
      end

      # A constant handler that simply yields — no wrapping applied.
      NOOP_AROUND_EACH_HANDLER = ->(_context, &block) { block.call }

      # Sets a middleware wrapper for every action invocation.
      #
      # The handler receives the context and a block; it must call the
      # block to let the action run.
      #
      # @example
      #   reducer.around_each ->(ctx, &blk) { TimeMeasure.measure(ctx, &blk) }
      #
      # @param handler [Proc] middleware that receives context and a block
      # @return [self]
      def around_each(handler)
        @around_each_handler = handler
        self
      end

      # Returns the custom around-each handler, or the no-op default.
      #
      # @return [Proc]
      def around_each_handler
        @around_each_handler || NOOP_AROUND_EACH_HANDLER
      end

      # Executes the pipeline of actions.
      #
      # Each action is invoked sequentially. If an action raises
      # {FailWithRollbackError}, the rollback sequence is triggered
      # immediately. An optional block receives the context and the
      # current action after each step (used by the logging decorator).
      #
      # @param actions [Array<Class, Proc>] one or more action classes
      #   (extending {Action}) or procs with a `#call` method
      # @return [Context] the context after all actions or rollback
      # @raise [RuntimeError] if the action list is empty
      def reduce(*actions)
        raise "No action(s) were provided" if actions.empty?

        actions.flatten!

        actions.each_with_index.with_object(context) do |(action, index), current_context|
          invoke_action(current_context, action)
        rescue FailWithRollbackError
          reduce_rollback(actions, index)
        ensure
          # For logging
          yield(current_context, action) if block_given?
        end
      end

      # Runs the rollback sequence in reverse order.
      #
      # Only actions up to (and including) the failing one are compensated,
      # in reverse execution order. Actions without a `rollback` class
      # method are skipped.
      #
      # @param actions [Array<Class, Proc>] the full action list
      # @param index_of_failed_action [Integer, nil] the index that raised
      # @return [Context] the context after rollback
      def reduce_rollback(actions, index_of_failed_action = nil)
        reversable_actions(actions, index_of_failed_action)
          .reverse
          .reduce(context) do |context, action|
            if action.respond_to?(:rollback)
              action.rollback(context)
            else
              context
            end
          end
      end

      private

      # Invokes a single action within the around-each wrapper.
      #
      # @param current_context [Context]
      # @param action [Class, Proc]
      # @return [void]
      def invoke_action(current_context, action)
        around_each_handler.call(current_context) do
          if action.respond_to?(:call)
            action.call(current_context)
          else
            action.execute(current_context)
          end
        end
      end

      # Returns the slice of actions eligible for rollback.
      #
      # Uses the tracked execution index rather than `actions.index` so
      # that duplicated action classes roll back correctly.
      #
      # @param actions [Array]
      # @param index_of_failed_action [Integer, nil]
      # @return [Array]
      def reversable_actions(actions, index_of_failed_action = nil)
        # L'indice viene tracciato nel reduce: actions.index troverebbe la prima
        # occorrenza e con azioni duplicate il rollback sarebbe parziale
        index_of_failed_action ||= actions.index(@context.current_action) || 0

        # Reverse from the point where the fail was triggered
        actions.take(index_of_failed_action + 1)
      end
    end
  end
end
