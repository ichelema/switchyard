# frozen_string_literal: true

module Switchyard
  # Helpers for testing Switchyard workflows.
  #
  # {ContextFactory} lets you intercept the context at a specific action
  # boundary, allowing unit tests that inspect the context mid-pipeline
  # without running the rest of the workflow.
  #
  # @example
  #   ctx = Switchyard::Testing::ContextFactory
  #           .make_from(MyOrganizer)
  #           .for(MyAction)
  #           .with(:input => 42)
  #   expect(ctx.number).to eq(42)
  #
  module Testing
    # Captures the context at a specific action boundary.
    class ContextFactory
      # @return [Module] the organizer under test
      attr_reader :organizer

      # Creates a factory for the given organizer.
      #
      # @param organizer [Module] the organizer class
      # @return [ContextFactory]
      def self.make_from(organizer)
        new(organizer)
      end

      # Sets the action at which to intercept the context.
      #
      # @param action [Class] the action class (extending {Action})
      # @return [self]
      def for(action)
        @target_action = action
        self
      end

      # Invokes the organizer and returns the context at the target action.
      #
      # A before-action hook captures the context right before the target
      # action executes. The hook is removed after the call.
      #
      # Forwards arguments to the organizer's `call` method.
      # @return [Context] the context at interception point
      def with(...)
        hook = nil
        hook = ->(ctx) do
          if ctx.current_action == @target_action
            # L'hook non deve essere re-invocato quando il context
            # verra' usato con Action#execute nel test
            ctx[:_before_actions].delete(hook)

            throw(:return_ctx_from_execution, ctx)
          end
        end

        @organizer.append_before_actions(hook)

        begin
          catch(:return_ctx_from_execution) do
            @organizer.call(...)
          end
        ensure
          # L'hook e' per-chiamata: la classe organizer non deve conservarlo
          @organizer.remove_before_actions(hook)
        end
      end

      # @param organizer [Module] the organizer class
      def initialize(organizer)
        @organizer = organizer
      end
    end
  end
end
