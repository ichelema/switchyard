# frozen_string_literal: true

module FunctionalLightService
  module Organizer
    class ReduceIfElse
      extend ScopedReducable

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
