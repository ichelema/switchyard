# frozen_string_literal: true

module Switchyard
  module Organizer
    # Repeats steps until a condition returns true (post-condition loop).
    #
    # @example
    #   reduce_until(->(ctx) { ctx[:balance] <= 0 }, [DeductDues])
    #
    class ReduceUntil
      extend ScopedReducable

      # Builds a loop that runs at least once and stops when the condition
      # or {Context#stop_processing?} returns true.
      #
      # @param organizer [Module] the owning organizer
      # @param condition_block [Proc] receives the context, returns truthy
      #   when the loop should stop
      # @param steps [Array<Class, Proc>] actions per iteration
      # @return [Proc] callable step
      def self.run(organizer, condition_block, steps)
        ->(ctx) do
          return ctx if ctx.stop_processing?

          loop do
            ctx = scoped_reduce(organizer, ctx, steps)
            break if condition_block.call(ctx) || ctx.stop_processing?
          end

          ctx
        end
      end
    end
  end
end
