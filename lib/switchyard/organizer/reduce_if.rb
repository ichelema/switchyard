# frozen_string_literal: true

module Switchyard
  module Organizer
    # Conditionally executes steps when a predicate returns true.
    #
    # @example
    #   reduce_if(->(ctx) { ctx.user.active? }, [SendWelcomeEmail])
    #
    class ReduceIf
      extend ScopedReducable

      # Builds a lambda that conditionally runs steps.
      #
      # @param organizer [Module] the owning organizer
      # @param condition_block [Proc] receives the context, returns truthy
      #   when steps should run
      # @param steps [Array<Class, Proc>] actions to execute
      # @return [Proc] callable step
      def self.run(organizer, condition_block, steps)
        ->(ctx) do
          return ctx if ctx.stop_processing?

          ctx = scoped_reduce(organizer, ctx, steps) if condition_block.call(ctx)

          ctx
        end
      end
    end
  end
end
