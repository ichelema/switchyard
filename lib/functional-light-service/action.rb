# frozen_string_literal: true

module FunctionalLightService
  module Action
    def self.extended(base_class)
      base_class.extend Macros
      base_class.extend FunctionalLightService::Prelude::Result
    end

    def self.included(base_class)
      FunctionalLightService::Deprecations.warn(
        "Including FunctionalLightService::Action is deprecated; " \
        "use `extend FunctionalLightService::Action` instead"
      )
      base_class.extend Macros
    end

    module Macros
      def expects(*args)
        if expect_key_having_default?(args)
          available_defaults[args.first] = args.last[:default]

          args = [args.first]
        end

        expected_keys.concat(args)
      end

      def promises(*args)
        promised_keys.concat(args)
      end

      def expected_keys
        @expected_keys ||= []
      end

      def promised_keys
        @promised_keys ||= []
      end

      def executed
        define_singleton_method :execute do |context = {}|
          action_context = create_action_context(context)
          return action_context if action_context.stop_processing?

          # Store the action within the context
          action_context.current_action = self

          Context::KeyVerifier.verify_keys(action_context, self) do
            action_context.define_accessor_methods_for_keys(all_keys)

            catch(:jump_when_failed) do
              call_before_action(action_context)
              yield(action_context)
              call_after_action(action_context)
            end
          end
        end
      end

      def rolled_back
        msg = "`rolled_back` macro can not be invoked again"
        raise msg if respond_to?(:rollback)

        define_singleton_method :rollback do |context = {}|
          yield(context)

          context
        end
      end

      private

      def create_action_context(context)
        # I default vanno applicati anche quando l'action gira dentro un
        # organizer (il context è già un Context): prima dell'early return.
        # Il guard sull'ivar evita lavoro (e scritture lazy) nel percorso caldo
        apply_expects_defaults(context) if @available_defaults

        return context if context.is_a? FunctionalLightService::Context

        FunctionalLightService::Context.make(context)
      end

      def apply_expects_defaults(context)
        usable_defaults(context).each do |ctx_key, default|
          context[ctx_key] = extract_default(default, context)
        end
      end

      def available_defaults
        @available_defaults ||= {}
      end

      def expect_key_having_default?(key)
        return false unless key.size == 2 && key.last.is_a?(Hash)
        return true if key.last.key?(:default)

        bad_key = key.last.keys.first
        err_msg = "Specify defaults with a `default` key. You have #{bad_key}."
        raise UnusableExpectKeyDefaultError, err_msg
      end

      def missing_expected_keys(context)
        # context.key? risolve anche gli alias: `expected_keys - context.keys`
        # (upstream) darebbe falsi mancanti sulle chiavi aliasate
        expected_keys.reject { |key| context.key?(key) }
      end

      def usable_defaults(context)
        available_defaults.slice(
          *(missing_expected_keys(context) & available_defaults.keys)
        )
      end

      def extract_default(default, context)
        return default unless default.respond_to?(:call)

        default.call(context)
      end

      def all_keys
        expected_keys + promised_keys
      end

      def call_before_action(context)
        invoke_callbacks(context[:_before_actions], context)
      end

      def call_after_action(context)
        invoke_callbacks(context[:_after_actions], context)
      end

      def invoke_callbacks(callbacks, context)
        return context unless callbacks

        callbacks.each do |cb|
          cb.call(context)
        end

        context
      end
    end
  end
end
