# frozen_string_literal: true

require 'dry/inflector'

module Switchyard
  # Adapter built-in basato su LocalizationMap: nessuna dipendenza da I18n.
  # Viene selezionato da Configuration quando la costante ::I18n non esiste
  class LocalizationAdapter
    INFLECTOR = Dry::Inflector.new

    def failure(message_or_key, action_class, options = {})
      find_translated_message(message_or_key,
                              INFLECTOR.underscore(action_class.to_s),
                              options.merge(:type => :failures))
    end

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
