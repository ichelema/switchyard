# frozen_string_literal: true

require 'dry/inflector'

module Switchyard
  # Built-in localisation adapter using a static {LocalizationMap}.
  #
  # Has no dependency on the `i18n` gem. Auto-selected by
  # {Configuration} when `::I18n` is not loaded.
  #
  # @see I18n::LocalizationAdapter for the I18n-backed variant
  class LocalizationAdapter
    # @return [Dry::Inflector] used to underscore action class names
    INFLECTOR = Dry::Inflector.new

    # Looks up or returns a failure message.
    #
    # When `message_or_key` is a `Symbol`, it is looked up in the
    # {LocalizationMap}; otherwise returned verbatim.
    #
    # @param message_or_key [String, Symbol] literal message or lookup key
    # @param action_class [Class] the action class for scoping
    # @param options [Hash] extra options
    # @return [String] the resolved message
    def failure(message_or_key, action_class, options = {})
      find_translated_message(message_or_key,
                              INFLECTOR.underscore(action_class.to_s),
                              options.merge(:type => :failures))
    end

    # Looks up or returns a success message.
    #
    # @param message_or_key [String, Symbol] literal message or lookup key
    # @param action_class [Class] the action class for scoping
    # @param options [Hash] extra options
    # @return [String] the resolved message
    def success(message_or_key, action_class, options = {})
      find_translated_message(message_or_key,
                              INFLECTOR.underscore(action_class.to_s),
                              options.merge(:type => :successes))
    end

    private

    def find_translated_message(message_or_key, action_class, options)
      if message_or_key.is_a?(Symbol)
        Switchyard::LocalizationMap.instance.dig(
          Switchyard::Configuration.locale,
          action_class.to_sym,
          :switchyard,
          options[:type],
          message_or_key
        )
      else
        message_or_key
      end
    end
  end
end
