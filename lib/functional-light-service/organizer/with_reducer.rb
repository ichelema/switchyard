# frozen_string_literal: true

module FunctionalLightService
  module Organizer
    class WithReducer
      attr_reader :context
      attr_accessor :organizer

      def initialize(monitored_organizer = nil)
        @organizer = monitored_organizer
      end

      def with(data = {})
        @context = FunctionalLightService::Context.make(data)
        @context.organized_by = organizer
        self
      end

      # Handler di default condiviso: prima veniva creata una classe anonima
      # per ogni WithReducer senza around_each
      NOOP_AROUND_EACH_HANDLER = ->(_context, &block) { block.call }

      def around_each(handler)
        @around_each_handler = handler
        self
      end

      def around_each_handler
        @around_each_handler || NOOP_AROUND_EACH_HANDLER
      end

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

      def invoke_action(current_context, action)
        around_each_handler.call(current_context) do
          if action.respond_to?(:call)
            action.call(current_context)
          else
            action.execute(current_context)
          end
        end
      end

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
