# frozen_string_literal: true

module Switchyard
  module Organizer
    # Conditionally executes one of two action groups.
    #
    # @example
    #   reduce_if_else(->(ctx) { ctx.paid? }, [SendReceipt], [SendInvoice])
    #
    class ReduceIfElse
      extend ScopedReducable

      # Builds a lambda that branches on the condition.
      #
      # @param organizer [Module] the owning organizer
      # @param condition_block [Proc] receives the context, returns truthy
      #   for the `if_steps` branch
      # @param if_steps [Array<Class, Proc>] actions when condition is true
      # @param else_steps [Array<Class, Proc>] actions when condition is false
      # @return [Proc] callable step
      def self.run(organizer, condition_block, if_steps, else_steps)
        ->(ctx) do
          return ctx if ctx.stop_processing?

          ctx = if condition_block.call(ctx)
                  scoped_reduce(organizer, ctx, if_steps)
                else
                  scoped_reduce(organizer, ctx, else_steps)
                end

          ctx
        end
      end
    end
  end
end
