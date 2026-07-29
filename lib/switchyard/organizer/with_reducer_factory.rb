# frozen_string_literal: true

module Switchyard
  module Organizer
    class WithReducerFactory
      def self.make(monitored_organizer)
        logger = monitored_organizer.logger || Switchyard::Configuration.logger
        decorated = WithReducer.new(monitored_organizer)

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
