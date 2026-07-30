# frozen_string_literal: true

module Switchyard
  module Organizer
    # Repeats steps while a condition returns true (pre-condition loop).
    #
    # The condition is checked **before** each iteration. Unlike
    # {ReduceUntil}, a scoped reduce is **not** used, so the `skip_remaining`
    # flag is reset manually around the loop body.
    #
    # @example
    #   reduce_while(->(ctx) { ctx[:balance] > 0 }, [DeductDues])
    #
    class ReduceWhile
      # Builds a loop that runs zero or more times.
      #
      # @param organizer [Module] the owning organizer
      # @param condition_block [Proc] receives the context, returns truthy
      #   while the loop should continue
      # @param steps [Array<Class, Proc>] actions to repeat
      # @return [Proc] callable step
      def self.run(organizer, condition_block, steps)
        ->(ctx) do
          return ctx if ctx.stop_processing?

          reset_skip(ctx)

          Array(steps).each do |step|
            break unless condition_block.call(ctx)

            ctx = organizer.with(ctx).reduce([step])
            break if ctx.stop_processing?
          end

          reset_skip(ctx)

          ctx
        end
      end

      # Resets the `skip_remaining` flag unless the context has failed or
      # a `skip_all_remaining` is active.
      #
      # @api private
      # @param ctx [Context]
      def self.reset_skip(ctx)
        ctx.reset_skip_remaining! unless ctx.failure? || ctx.skip_all_remaining?
      end
      private_class_method :reset_skip
    end
  end
end
