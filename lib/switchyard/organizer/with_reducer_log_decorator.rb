# frozen_string_literal: true

module Switchyard
  module Organizer
    # Decorates a {WithReducer} with structured logging.
    #
    # Logs the organiser name, context keys, expected and promised keys,
    # failures and skip decisions. Logging happens at most once per
    # pipeline run (guarded by the {#logged?} flag).
    #
    # @example
    #   WithReducerLogDecorator.new(
    #     MyOrganizer,
    #     :decorated => WithReducer.new,
    #     :logger => Logger.new($stdout)
    #   ).with(data).reduce(steps)
    #
    class WithReducerLogDecorator
      # @return [Boolean] whether a failure or skip has already been logged
      attr_reader :logged

      # @return [Logger] the logger instance
      attr_reader :logger

      # @return [WithReducer] the decorated reducer
      attr_reader :decorated

      # @return [Module] the owning organizer
      attr_reader :organizer

      alias logged? logged

      # @param organizer [Module] the owning organizer
      # @param logger [Logger] the logger instance
      # @param decorated [WithReducer] the reducer to decorate
      def initialize(organizer, logger:, decorated: WithReducer.new)
        @decorated = decorated
        @organizer = organizer

        decorated.organizer = organizer

        @logger = logger
        @logged = false
      end

      # Initialises the context and logs the organiser call.
      #
      # @param data [Hash, Context] initial data
      # @return [self]
      def with(data = {})
        logger.info { "[Switchyard] - calling organizer <#{organizer}>" }

        decorated.with(data)

        logger.info do
          "[Switchyard] -     keys in context: " \
            "#{extract_keys(decorated.context.keys)}"
        end
        self
      end

      # Sets an around-each handler on the decorated reducer.
      #
      # @param handler [Proc]
      # @return [self]
      def around_each(handler)
        decorated.around_each(handler)
        self
      end

      # Executes the pipeline with logging callbacks.
      #
      # After each action, logs the execution details, failure, or skip
      # status — but only once per pipeline run.
      #
      # @param actions [Array<Class, Proc>] actions to execute
      # @return [Context]
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

      # Logs the executing action and its expected / promised keys.
      #
      # @param action [Class] the action class
      # @param context [Context]
      def write_log(action, context)
        return unless logger.info?

        logger.info("[Switchyard] - executing <#{action}>")
        log_expects(action)
        log_promises(action)
        logger.info("[Switchyard] -     keys in context: "\
                    "#{extract_keys(context.keys)}")
      end

      # Logs the expected keys of an action, if any are defined.
      #
      # @param action [Class]
      def log_expects(action)
        return unless defined?(action.expects) && action.expects.any?

        logger.info("[Switchyard] -   expects: " \
                    "#{extract_keys(action.expects)}")
      end

      # Logs the promised keys of an action, if any are defined.
      #
      # @param action [Class]
      def log_promises(action)
        return unless defined?(action.promises) && action.promises.any?

        logger.info("[Switchyard] -   promises: " \
                    "#{extract_keys(action.promises)}")
      end

      # Formats a list of keys for the log output.
      #
      # @param keys [Array<Symbol>]
      # @return [String]
      def extract_keys(keys)
        keys.map { |key| ":#{key}" }.join(', ')
      end

      # Checks whether the context indicates a failure.
      #
      # @param context [Context]
      # @return [Boolean]
      def has_failure?(context)
        context.respond_to?(:failure?) && context.failure?
      end

      # Writes the failure log entry.
      #
      # @param context [Context]
      # @param action [Class]
      def write_failure_log(context, action)
        logger.warn("[Switchyard] - :-((( <#{action}> has failed...")
        logger.warn("[Switchyard] - context message: #{context.message}")
        @logged = true
      end

      # Checks whether the context indicates a skip state.
      #
      # @param context [Context]
      # @return [Boolean]
      def skip_remaining?(context)
        (context.respond_to?(:skip_remaining?) && context.skip_remaining?) ||
          (context.respond_to?(:skip_all_remaining?) && context.skip_all_remaining?)
      end

      # Writes the skip log entry.
      #
      # @param context [Context]
      # @param action [Class]
      def write_skip_remaining_log(context, action)
        return unless logger.info?

        msg = "[Switchyard] - ;-) <#{action}> has decided " \
              "to skip the rest of the actions"
        logger.info(msg)
        logger.info("[Switchyard] - context message: #{context.message}")
        @logged = true
      end
    end
  end
end
