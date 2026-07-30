# frozen_string_literal: true

module Switchyard
  class Context
    # Verifies that expected and promised keys are satisfied before and after
    # an {Action} execution, and that no declared key collides with
    # Switchyard infrastructure keys.
    #
    # @see Action::Macros#expects
    # @see Action::Macros#promises
    class KeyVerifier
      # @return [Context] the context being verified
      attr_reader :context

      # @return [Class] the action whose keys are verified
      attr_reader :action

      # @param context [Context]
      # @param action [Class] the action class (extending {Action})
      def initialize(context, action)
        @context = context
        @action = action
      end

      # Checks whether all given keys exist in the context (alias-aware).
      #
      # @param keys [Array<Symbol>] the keys to check
      # @return [Boolean]
      def are_all_keys_in_context?(keys)
        not_found_keys = keys_not_found(keys)
        not_found_keys.none?
      end

      # Returns the subset of keys that are not present in the context.
      #
      # The check is alias-aware: a key that maps to an alias that is present
      # is considered satisfied.
      #
      # @param keys [Array<Symbol>] keys to check
      # @return [Array<Symbol>] missing keys
      def keys_not_found(keys)
        keys ||= context.keys
        # context.key? risolve anche gli alias
        keys.reject { |key| context.key?(key) }
      end

      # Formats a list of keys for error messages.
      #
      # @param keys [Array<Symbol>]
      # @return [String] e.g. `":foo, :bar"`
      def format_keys(keys)
        keys.map { |k| ":#{k}" }.join(', ')
      end

      # Builds a descriptive error message for missing keys.
      #
      # @return [String]
      def error_message
        "#{type_name} #{format_keys(keys_not_found(keys))} " \
          "to be in the context during #{action}"
      end

      # Template method — subclasses return whether the verification should
      # raise.
      #
      # @abstract
      # @param _keys [Array<Symbol>]
      # @return [Boolean]
      # @raise [NotImplementedError]
      def throw_error_predicate(_keys)
        raise NotImplementedError, 'Sorry, you have to override length'
      end

      # Runs the verification and raises on failure.
      #
      # @return [Context] the context (unchanged) when verification passes
      # @raise [ExpectedKeysNotInContextError]
      # @raise [PromisedKeysNotInContextError]
      # @raise [ReservedKeysInContextError]
      def verify
        return context if context.failure?

        if throw_error_predicate(keys)
          Configuration.logger.error error_message
          raise error_to_throw, error_message
        end

        context
      end

      # Runs all three verifications around an action execution block.
      #
      # Order: reserved keys → expected keys → block → promised keys.
      #
      # @param context [Context]
      # @param action [Class] the action class
      # @yield execution block (the action body)
      # @return [Object] the block's return value
      def self.verify_keys(context, action, &block)
        ReservedKeysVerifier.new(context, action).verify
        ExpectedKeyVerifier.new(context, action).verify

        block.call

        PromisedKeyVerifier.new(context, action).verify
      end
    end

    # Verifies that all keys declared via {Action::Macros#expects} are
    # present before the action runs.
    class ExpectedKeyVerifier < KeyVerifier
      # @return [String] `"expected"`
      def type_name
        "expected"
      end

      # @return [Array<Symbol>] keys declared with {Action::Macros#expects}
      def keys
        action.expected_keys
      end

      # @return [Class] {ExpectedKeysNotInContextError}
      def error_to_throw
        ExpectedKeysNotInContextError
      end

      # @param keys [Array<Symbol>]
      # @return [Boolean] `true` when any expected key is missing
      def throw_error_predicate(keys)
        !are_all_keys_in_context?(keys)
      end
    end

    # Verifies that all keys declared via {Action::Macros#promises} are
    # produced by the action block.
    class PromisedKeyVerifier < KeyVerifier
      # @return [String] `"promised"`
      def type_name
        "promised"
      end

      # @return [Array<Symbol>] keys declared with {Action::Macros#promises}
      def keys
        action.promised_keys
      end

      # @return [Class] {PromisedKeysNotInContextError}
      def error_to_throw
        PromisedKeysNotInContextError
      end

      # @param keys [Array<Symbol>]
      # @return [Boolean] `true` when any promised key is missing
      def throw_error_predicate(keys)
        !are_all_keys_in_context?(keys)
      end
    end

    # Verifies that expected and promised keys do not collide with
    # internal Switchyard keys.
    class ReservedKeysVerifier < KeyVerifier
      # Returns the subset of declared keys that are reserved.
      #
      # @return [Array<Symbol>] violating keys
      def violated_keys
        (action.promised_keys + action.expected_keys) & reserved_keys
      end

      # @return [String] error message listing violated keys
      def error_message
        "promised or expected keys cannot be a " \
          "reserved key: [#{format_keys(violated_keys)}]"
      end

      # @return [Array<Symbol>] violated keys
      def keys
        violated_keys
      end

      # @return [Class] {ReservedKeysInContextError}
      def error_to_throw
        ReservedKeysInContextError
      end

      # @param keys [Array<Symbol>]
      # @return [Boolean] `true` when any violation exists
      def throw_error_predicate(keys)
        keys.any?
      end

      # The list of key names that Switchyard reserves for itself.
      #
      # These are set on the context by {Organizer::ClassMethods#with} and
      # must not be used in `expects` or `promises`.
      #
      # @return [Array<Symbol>] `[:message, :error_code, :current_action,
      #   :organized_by, :_aliases, :_before_actions, :_after_actions]`
      def reserved_keys
        # _aliases/_before_actions/_after_actions sono chiavi infrastrutturali
        # scritte da Organizer.with nel context
        %i[message error_code current_action organized_by
           _aliases _before_actions _after_actions].freeze
      end
    end
  end
end
