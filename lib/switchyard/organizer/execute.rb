# frozen_string_literal: true

module Switchyard
  module Organizer
    # Wraps an inline lambda or block into an executable step.
    #
    # Used by {ClassMethods#execute} and {ClassMethods#add_to_context} to
    # turn plain procs into pipeline steps.
    #
    # @example
    #   Execute.run(->(ctx) { ctx[:logged] = true })
    #
    class Execute
      # Builds a lambda that calls the code block and returns the context.
      #
      # @param code_block [Proc] the lambda or proc to execute
      # @return [Proc] callable step
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
