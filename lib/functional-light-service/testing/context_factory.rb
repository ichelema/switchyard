module FunctionalLightService
  module Testing
    class ContextFactory
      attr_reader :organizer

      def self.make_from(organizer)
        new(organizer)
      end

      def for(action)
        @target_action = action
        self
      end

      # More than one arguments can be passed to the
      # Organizer's #call method
      def with(*args, &block)
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
            @organizer.call(*args, &block)
          end
        ensure
          # L'hook e' per-chiamata: la classe organizer non deve conservarlo
          @organizer.remove_before_actions(hook)
        end
      end

      def initialize(organizer)
        @organizer = organizer
      end
    end
  end
end
