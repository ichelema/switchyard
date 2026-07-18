# frozen_string_literal: true

module FunctionalLightService
  class Configuration
    class << self
      attr_writer :logger, :localization_adapter, :locale

      def logger
        @logger = _default_logger unless instance_variable_defined?("@logger")
        @logger
      end

      def localization_adapter
        # La gem i18n non è una dipendenza: l'adapter I18n viene scelto solo
        # se la costante è già stata caricata dall'applicazione ospite
        @localization_adapter ||= if Module.const_defined?('I18n')
                                    FunctionalLightService::I18n::LocalizationAdapter.new
                                  else
                                    LocalizationAdapter.new
                                  end
      end

      def locale
        @locale ||= :en
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
