# frozen_string_literal: true

module Switchyard
  module Organizer
    # Wraps a set of steps with a before / after callback action.
    #
    # The callback action receives the context and must call `yield` in
    # between (middleware style). Supports up to two nested levels.
    #
    # @example
    #   with_callback(->(ctx, &blk) { TimeMeasure.measure(ctx, &blk) },
    #                 [FetchData, TransformData])
    #
    class WithCallback
      extend ScopedReducable

      # Builds a lambda that installs the callback, runs the action, and
      # restores any previous callback.
      #
      # @param organizer [Module] the owning organizer
      # @param action [Class] an action (extending {Action}) that acts as
      #   middleware
      # @param steps [Array<Class, Proc>] actions wrapped by the callback
      # @return [Proc] callable step
      def self.run(organizer, action, steps)
        ->(ctx) do
          return ctx if ctx.stop_processing?

          # This will only allow 2 level deep nesting of callbacks
          previous_callback = ctx[:callback]

          ctx[:callback] = ->(context) do
            ctx = scoped_reduce(organizer, context, steps)
            ctx
          end

          ctx = action.execute(ctx)
          ctx[:callback] = previous_callback

          ctx
        end
      end
    end
  end
end
