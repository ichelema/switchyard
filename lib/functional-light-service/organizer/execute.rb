module FunctionalLightService
  module Organizer
    class Execute
      def self.run(code_block)
        ->(ctx) do
          return ctx if ctx.stop_processing?

          code_block.call(ctx)
          ctx
        end
      end
    end
  end
end
