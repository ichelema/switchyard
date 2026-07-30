# frozen_string_literal: true

require 'dry/inflector'

module Switchyard
  # Namespace for the {LocalizationAdapter I18n-backed localisation adapter}.
  module I18n
    # Localisation adapter backed by the `i18n` gem.
    #
    # Auto-selected by {Configuration} when `::I18n` is loaded. Uses
    # `I18n.t` to translate symbol keys into locale-specific strings.
    #
    # The translation scope is derived from the action class name:
    # `<underscored_action_name>.switchyard.<type>`.
    #
    class LocalizationAdapter
      # Looks up or returns a failure message via `I18n.t`.
      #
      # @param message_or_key [String, Symbol] literal or I18n key
      # @param action_class [Class] the action class
      # @param i18n_options [Hash] extra I18n options
      # @return [String]
      def failure(message_or_key, action_class, i18n_options = {})
        find_translated_message(message_or_key,
                                action_class,
                                i18n_options,
                                :type => :failure)
      end

      # Looks up or returns a success message via `I18n.t`.
      #
      # @param message_or_key [String, Symbol] literal or I18n key
      # @param action_class [Class] the action class
      # @param i18n_options [Hash] extra I18n options
      # @return [String]
      def success(message_or_key, action_class, i18n_options = {})
        find_translated_message(message_or_key,
                                action_class,
                                i18n_options,
                                :type => :success)
      end

      private

      def find_translated_message(message_or_key,
                                  action_class,
                                  i18n_options,
                                  type)
        if message_or_key.is_a?(Symbol)
          translate(message_or_key, action_class, i18n_options.merge(type))
        else
          message_or_key
        end
      end

      def translate(key, action_class, options = {})
        type = options.delete(:type)

        scope = i18n_scope_from_class(action_class, type)
        options[:scope] = scope

        ::I18n.t(key, **options)
      end

      def i18n_scope_from_class(action_class, type)
        inflector = Dry::Inflector.new
        "#{inflector.underscore(action_class.name)}.switchyard.#{inflector.pluralize(type)}"
      end
    end
  end
end
