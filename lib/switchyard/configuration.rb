# frozen_string_literal: true

module Switchyard
  # Global configuration for Switchyard.
  #
  # Controls logging, message localisation, and the locale used for
  # success/failure messages. All accessors are class-level setters;
  # configure at boot time before any action runs.
  #
  # @example
  #   Switchyard::Configuration.logger = Rails.logger
  #   Switchyard::Configuration.locale = :it
  #
  # @see LocalizationAdapter
  # @see I18n::LocalizationAdapter
  class Configuration
    class << self
      # Sets the logger used across all organizers and actions.
      #
      # @param value [Logger] a logger instance
      attr_writer :logger

      # Sets the localisation adapter for success/failure messages.
      #
      # @param value [#success, #failure] an adapter instance
      attr_writer :localization_adapter

      # Sets the locale for localised messages.
      #
      # @param value [Symbol] locale name (e.g. `:en`, `:it`)
      attr_writer :locale

      # Returns the current logger.
      #
      # Defaults to a `Logger` writing to `nil` at `WARN` level.
      #
      # @return [Logger]
      def logger
        @logger = _default_logger unless instance_variable_defined?("@logger")
        @logger
      end

      # Returns the current localisation adapter.
      #
      # Auto-selects at first call: if the host application has loaded
      # `::I18n`, a {I18n::LocalizationAdapter} is returned; otherwise
      # the built-in {LocalizationAdapter} (hash-based) is used.
      #
      # @return [LocalizationAdapter, I18n::LocalizationAdapter]
      def localization_adapter
        # La gem i18n non è una dipendenza: l'adapter I18n viene scelto solo
        # se la costante è già stata caricata dall'applicazione ospite
        @localization_adapter ||= if Module.const_defined?('I18n')
                                    Switchyard::I18n::LocalizationAdapter.new
                                  else
                                    LocalizationAdapter.new
                                  end
      end

      # Returns the current locale.
      #
      # @return [Symbol] defaults to `:en`
      def locale
        @locale ||= :en
      end

      private

      # Builds the default logger (writes nowhere, WARN level).
      #
      # @api private
      # @return [Logger]
      def _default_logger
        logger = Logger.new(nil)
        logger.level = Logger::WARN
        logger
      end
    end
  end
end
