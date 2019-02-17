module FunctionalLightService
  module Organizer
    class WithReducerFactory
      def self.make(monitored_organizer)
        logger = monitored_organizer.logger || FunctionalLightService::Configuration.logger
        decorated = WithReducer.new

        return decorated if logger.nil?

        WithReducerLogDecorator.new(
          monitored_organizer,
          :decorated => decorated,
          :logger => logger
        )
      end
    end
  end
end
