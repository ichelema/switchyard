module FunctionalLightService
  class Configuration
    class << self
      attr_writer :logger, :localization_adapter

      def logger
        @logger = _default_logger unless instance_variable_defined?("@logger")
        @logger
      end

      def localization_adapter
        @localization_adapter ||= LocalizationAdapter.new
      end

      private

      def _default_logger
        logger = Logger.new(nil)
        logger.level = Logger::WARN
        logger
      end
    end
  end
end
