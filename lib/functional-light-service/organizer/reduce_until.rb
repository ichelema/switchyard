# frozen_string_literal: true

module FunctionalLightService
  module Organizer
    class ReduceUntil
      extend ScopedReducable

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
