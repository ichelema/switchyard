# frozen_string_literal: true

module Switchyard
  # Defines a single step in an {Organizer} workflow.
  #
  # Extend this module in a class, declare its input and output keys with
  # {Macros#expects} and {Macros#promises}, then implement the step with
  # {Macros#executed}. Actions receive a mutable {Context} and return that same
  # context after execution.
  #
  # @example Define and execute an action
  #   class AddTax
  #     extend Switchyard::Action
  #
  #     expects :subtotal
  #     promises :total
  #
  #     executed do |context|
  #       context.total = context.subtotal * 1.2
  #     end
  #   end
  #
  #   result = AddTax.execute(:subtotal => 100)
  #   result.total # => 120.0
  #
  # @see Organizer
  # @see Context
  module Action
    # Sets up the action DSL on the extending class.
    #
    # @api private
    # @param base_class [Class] class extending {Action}
    # @return [void]
    def self.extended(base_class)
      base_class.extend Macros
      base_class.extend Switchyard::Prelude::Result
    end

    # Supports the deprecated `include Switchyard::Action` form.
    #
    # @deprecated Use `extend Switchyard::Action` instead.
    # @api private
    # @param base_class [Class] class including {Action}
    # @return [void]
    def self.included(base_class)
      Switchyard::Deprecations.warn(
        "Including Switchyard::Action is deprecated; " \
        "use `extend Switchyard::Action` instead"
      )
      base_class.extend Macros
    end

    # Class-level DSL added to action classes.
    module Macros
      # Declares keys that must be present before the action runs.
      #
      # A key may define a fallback with `:default`. Callable defaults receive
      # the current input object (`Hash` or {Context}). Missing required keys
      # raise {ExpectedKeysNotInContextError} before the execution block runs.
      #
      # @example Required keys
      #   expects :user, :mailer
      # @example Static default
      #   expects :currency, :default => "EUR"
      # @example Callable default
      #   expects :locale, :default => ->(context) { context.user.locale }
      #
      # @param args [Array<Symbol>, (Symbol, Hash)] required keys, optionally
      #   followed by a `:default` option for one key
      # @return [Array<Symbol>] all keys expected by the action
      # @raise [UnusableExpectKeyDefaultError] if the option is not named
      #   `:default`
      def expects(*args)
        if expect_key_having_default?(args)
          available_defaults[args.first] = args.last[:default]

          args = [args.first]
        end

        expected_keys.concat(args)
      end

      # Declares keys that the action must place in the context.
      #
      # Promised keys also gain reader and writer accessors inside the execution
      # block. A successful action that omits one raises
      # {PromisedKeysNotInContextError}.
      #
      # @example
      #   promises :order, :receipt
      #
      # @param args [Array<Symbol>] keys produced by the action
      # @return [Array<Symbol>] all keys promised by the action
      def promises(*args)
        promised_keys.concat(args)
      end

      # Returns all keys declared through {#expects}.
      #
      # @return [Array<Symbol>]
      def expected_keys
        @expected_keys ||= []
      end

      # Returns all keys declared through {#promises}.
      #
      # @return [Array<Symbol>]
      def promised_keys
        @promised_keys ||= []
      end

      # Defines the action body and creates the class-level `execute` method.
      #
      # Before yielding, Switchyard applies missing defaults, verifies expected
      # keys, exposes declared keys as context accessors, and invokes organizer
      # `before_actions` hooks. After a normal execution it invokes
      # `after_actions` hooks and verifies promised keys.
      #
      # @example
      #   executed do |context|
      #     context.full_name = "#{context.first_name} #{context.last_name}"
      #   end
      #
      # @yieldparam context [Context] context for the current execution
      # @return [Symbol] the name of the generated method (`:execute`)
      # @see Context#fail_and_return!
      # @see Context#fail_with_rollback!
      def executed
        # Executes the action against a hash or an existing context.
        #
        # @param context [Hash, Context] initial data or an existing context
        # @return [Context] the context after execution
        # @raise [ExpectedKeysNotInContextError] when a required key is missing
        # @raise [PromisedKeysNotInContextError] when a successful action does
        #   not produce every promised key
        # @raise [ReservedKeysInContextError] when a declared key conflicts
        #   with Switchyard infrastructure or an existing context method
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

      # Defines compensation logic for an action that requests rollback.
      #
      # The generated class-level `rollback` method is called by the organizer
      # in reverse execution order after {Context#fail_with_rollback!}.
      #
      # @example
      #   rolled_back do |context|
      #     context.inventory.release(context.order)
      #   end
      #
      # @yieldparam context [Context] failed workflow context
      # @return [Symbol] the name of the generated method (`:rollback`)
      # @raise [RuntimeError] if rollback logic was already defined
      def rolled_back
        msg = "`rolled_back` macro can not be invoked again"
        raise msg if respond_to?(:rollback)

        # Compensates the action after a rollback-triggering failure.
        #
        # @param context [Context] failed workflow context
        # @return [Context] the same context after compensation
        define_singleton_method :rollback do |context = {}|
          yield(context)

          context
        end
      end

      private

      def create_action_context(context)
        # Defaults must be applied even when the action runs inside an
        # organizer (the context is already a Context): before the early
        # return. The ivar guard avoids work (and lazy writes) on the hot path
        apply_expects_defaults(context) if @available_defaults

        return context if context.is_a? Switchyard::Context

        Switchyard::Context.make(context)
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
