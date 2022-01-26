module FunctionalLightService
  module Organizer
    class WithReducerLogDecorator
      attr_reader :logged, :logger, :decorated, :organizer

      alias logged? logged

      def initialize(organizer, logger:, decorated: WithReducer.new)
        @decorated = decorated
        @organizer = organizer
        @logger = logger
        @logged = false
      end

      def with(data = {})
        logger.info { "[FunctionalLightService] - calling organizer <#{organizer}>" }

        decorated.with(data)

        logger.info do
          "[FunctionalLightService] -     keys in context: " \
            "#{extract_keys(decorated.context.keys)}"
        end
        self
      end

      def around_each(handler)
        decorated.around_each(handler)
        self
      end

      def reduce(*actions)
        decorated.reduce(*actions) do |context, action|
          next context if logged?

          if has_failure?(context)
            write_failure_log(context, action)
            next context
          end

          if skip_remaining?(context)
            write_skip_remaining_log(context, action)
            next context
          end

          write_log(action, context)
        end
      end

      private

      def write_log(action, context)
        return unless logger.info?

        logger.info("[FunctionalLightService] - executing <#{action}>")
        log_expects(action)
        log_promises(action)
        logger.info("[FunctionalLightService] -     keys in context: "\
                    "#{extract_keys(context.keys)}")
      end

      def log_expects(action)
        return unless defined?(action.expects) && action.expects.any?

        logger.info("[FunctionalLightService] -   expects: " \
                    "#{extract_keys(action.expects)}")
      end

      def log_promises(action)
        return unless defined?(action.promises) && action.promises.any?

        logger.info("[FunctionalLightService] -   promises: " \
                    "#{extract_keys(action.promises)}")
      end

      def extract_keys(keys)
        keys.map { |key| ":#{key}" }.join(', ')
      end

      def has_failure?(context)
        context.respond_to?(:failure?) && context.failure?
      end

      def write_failure_log(context, action)
        logger.warn("[FunctionalLightService] - :-((( <#{action}> has failed...")
        logger.warn("[FunctionalLightService] - context message: #{context.message}")
        @logged = true
      end

      def skip_remaining?(context)
        context.respond_to?(:skip_remaining?) && context.skip_remaining?
      end

      def write_skip_remaining_log(context, action)
        return unless logger.info?

        msg = "[FunctionalLightService] - ;-) <#{action}> has decided " \
              "to skip the rest of the actions"
        logger.info(msg)
        logger.info("[FunctionalLightService] - context message: #{context.message}")
        @logged = true
      end
    end
  end
end
