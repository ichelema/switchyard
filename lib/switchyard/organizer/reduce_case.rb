# frozen_string_literal: true

module Switchyard
  module Organizer
    # Dispatches execution based on a context value (pattern-match-style).
    #
    # Reads a key from the context, matches its value against a hash of
    # cases, and executes the corresponding steps. A `:default` fallback
    # is used when no case matches.
    #
    # @example
    #   reduce_case(
    #     :value => :status,
    #     :when  => { "pending" => [ValidatePayment], "shipped" => [Notify] },
    #     :else  => [LogUnknownStatus]
    #   )
    #
    class ReduceCase
      extend ScopedReducable

      # Validated keyword arguments for the case dispatch.
      class Arguments
        # @return [Symbol] the context key to read
        attr_reader :value

        # @return [Hash] mapping of values to action lists
        attr_reader :when

        # @return [Array<Class, Proc>] fallback steps
        attr_reader :else

        # @param args [Hash] must include `:value`, `:when` and `:else`
        # @raise [ArgumentError] if any mandatory key is missing
        def initialize(**args)
          validate_arguments(**args)
          @value = args[:value]
          @when = args[:when]
          @else = args[:else]
        end

        private

        # rubocop:disable Style/MultilineIfModifier
        def validate_arguments(**args)
          raise(
            ArgumentError,
            "Expected keyword arguments: [:value, :when, :else]. Given: #{args.keys}"
          ) unless args.keys.intersection(mandatory_arguments).count == mandatory_arguments.count
        end
        # rubocop:enable Style/MultilineIfModifier

        def mandatory_arguments
          %i[value when else]
        end
      end

      # Builds a lambda that dispatches on a context value.
      #
      # @param organizer [Module] the owning organizer
      # @param args [Hash] keyword arguments for {Arguments}
      # @return [Proc] callable step
      def self.run(organizer, **args)
        arguments = Arguments.new(**args)

        ->(ctx) do
          return ctx if ctx.stop_processing?

          matched_case = arguments.when.keys.find { |k| k.eql?(ctx[arguments.value]) }
          steps = arguments.when[matched_case] || arguments.else

          ctx = scoped_reduce(organizer, ctx, steps)

          ctx
        end
      end
    end
  end
end
