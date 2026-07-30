# frozen_string_literal: true

module Switchyard
  module Organizer
    # Factory that builds a {WithReducer}, optionally wrapped in a
    # {WithReducerLogDecorator} when a logger is configured.
    #
    class WithReducerFactory
      # Creates a reducer, decorating it with logging if a logger is
      # available.
      #
      # @param monitored_organizer [Module] the owning organizer class
      # @return [WithReducer, WithReducerLogDecorator]
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
