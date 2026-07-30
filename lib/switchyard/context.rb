# frozen_string_literal: true

module Switchyard
  # rubocop:disable Metrics/ClassLength
  # A mutable data envelope passed through an {Organizer} pipeline.
  #
  # Context extends `Hash` and tracks the execution outcome alongside the
  # data. Every {Action} reads from and writes to the same context instance.
  #
  # Use the factory method {.make} to create a new context; inside actions
  # the context is already set up by the organizer.
  #
  # @example Creating and using a context
  #   ctx = Switchyard::Context.make(:user => "alice", :role => "admin")
  #   ctx.succeed!("User loaded")
  #   ctx.success?  # => true
  #   ctx.message   # => "User loaded"
  #
  # @example Checking for failure
  #   ctx.fail!("Validation failed", :error_code => 422)
  #   ctx.failure? # => true
  #   ctx.error_code # => 422
  #
  # @example Setting an alias
  #   ctx.assign_aliases(:user_name => :name)
  #   ctx[:name] = "bob"
  #   ctx[:user_name] # => "bob"
  #
  # @see Action
  # @see Organizer
  # @see Context::KeyVerifier
  class Context < Hash
    include Switchyard::Prelude::Option
    include Switchyard::Prelude::Result

    # @return [Switchyard::Result] the outcome as a `Success` or `Failure`
    #   monad holding `{message:, error:}`
    attr_reader :outcome

    # @return [Class, nil] the action currently being executed
    attr_accessor :current_action

    # @return [Module, nil] the organizer that created this context
    attr_accessor :organized_by

    # rubocop:disable Lint/MissingSuper
    # Builds a new context, copying key-value pairs from the input.
    #
    # @param context [#to_hash] initial data (default empty hash)
    # @param outcome [Switchyard::Result] initial outcome (default
    #   `Success(message: '', error: nil)`)
    # @return [Context] a new context instance
    def initialize(context = {},
                   outcome = Success(:message => '', :error => nil))
      @outcome = outcome
      @skip_remaining = false
      @skip_all_remaining = false
      context.to_hash.each { |k, v| self[k] = v }
    end
    # rubocop:enable Lint/MissingSuper

    # Creates a context from a Hash or an existing Context.
    #
    # If `context` already is a `Switchyard::Context` it is returned as-is,
    # after processing any `:_aliases` key. Otherwise a new {Context} is
    # allocated from the given hash.
    #
    # @example
    #   ctx = Switchyard::Context.make(:number => 42)
    #   ctx.number # => 42
    #
    # @param context [Hash, Context] source data
    # @return [Context]
    # @raise [ArgumentError] if context is neither a Hash nor a Context
    def self.make(context = {})
      unless context.is_a?(Hash) || context.is_a?(Switchyard::Context)
        msg = 'Argument must be Hash or Switchyard::Context'
        raise ArgumentError, msg
      end

      context = new(context) unless context.is_a?(Context)

      context.assign_aliases(context.delete(:_aliases)) if context[:_aliases]
      context
    end

    # Merges a hash of values into the context.
    #
    # This is the mechanism {Organizer::ClassMethods#add_to_context} uses
    # behind the scenes.
    #
    # @example
    #   ctx.add_to_context(:role => "admin", :locale => "it")
    #
    # @param values [Hash] key-value pairs to merge
    # @return [Context] self
    def add_to_context(values)
      merge! values
    end

    # Returns whether the outcome is a success.
    #
    # @return [Boolean]
    def success?
      @outcome.success?
    end

    # Returns whether the outcome is a failure.
    #
    # @return [Boolean]
    def failure?
      @outcome.failure?
    end

    # Returns whether {skip_remaining!} was called.
    #
    # @return [Boolean]
    def skip_remaining?
      @skip_remaining
    end

    # Returns whether {skip_all_remaining!} was called.
    #
    # @return [Boolean]
    def skip_all_remaining?
      @skip_all_remaining
    end

    # Clears the `skip_remaining` flag while preserving the outcome.
    #
    # Used by `ScopedReducable#scoped_reduce` to reset the flag at scope
    # boundaries. The outcome message set by `succeed!` or `skip_remaining!`
    # is not affected.
    #
    # @return [false]
    def reset_skip_remaining!
      # Resetta soltanto il flag: l'esito (e il suo messaggio) non vanno persi
      @skip_remaining = false
    end

    # The outcome message (human-readable).
    #
    # @return [String, nil] message set by the last outcome-changing call
    def message
      @outcome.value[:message]
    end

    # The numeric error code, if one was provided on failure.
    #
    # @return [Integer, nil]
    def error_code
      @outcome.value[:error]
    end

    # Marks the context as successful with an optional message.
    #
    # The message may be localised through the configured
    # {Configuration.localization_adapter}.
    #
    # @example
    #   ctx.succeed!("Order completed")
    #
    # @param message [String, nil] success message
    # @param options [Hash] options forwarded to the localisation adapter
    # @return [void]
    def succeed!(message = nil, options = {})
      message = Configuration.localization_adapter.success(message,
                                                           current_action,
                                                           options)
      @outcome = Success(:message => message)
    end

    # Marks the context as failed with a message and optional error code.
    #
    # The message may be localised. The caller's options hash is never
    # mutated (a defensive `dup` is taken).
    #
    # @example
    #   ctx.fail!("Validation error", :error_code => 400)
    #
    # @param message [String, nil] failure message
    # @param options_or_error_code [Hash, Integer] either a hash whose
    #   `:error_code` key is extracted, or a bare integer error code
    # @return [void]
    def fail!(message = nil, options_or_error_code = {})
      options_or_error_code ||= {}

      if options_or_error_code.is_a?(Hash)
        # dup: l'hash di opzioni appartiene al chiamante e non va mutato
        options = options_or_error_code.dup
        error_code = options.delete(:error_code)
      else
        error_code = options_or_error_code
        options = {}
      end

      message = Configuration.localization_adapter.failure(message,
                                                           current_action,
                                                           options)

      @outcome = Failure(:message => message, :error => error_code)
    end

    # Same as {#fail!} but immediately exits the action block via `throw`.
    #
    # Use this inside an action to fail **and** short-circuit the rest
    # of the execution block in one call.
    #
    # @example
    #   executed do |ctx|
    #     ctx.fail_and_return!("Invalid input") unless ctx.user
    #     # anything here is skipped when user is missing
    #   end
    #
    # @param args [Array] forwarded to {#fail!}
    # @return [void] never returns normally
    def fail_and_return!(*args)
      fail!(*args)
      throw(:jump_when_failed)
    end

    # Same as {#fail!} but raises {FailWithRollbackError} so the organizer
    # triggers compensation logic.
    #
    # @see Action::Macros#rolled_back
    # @param message [String, nil] failure message
    # @param error_code [Integer, nil] numeric error code
    # @return [void] never returns normally
    def fail_with_rollback!(message = nil, error_code = nil)
      fail!(message, error_code)
      raise FailWithRollbackError
    end

    # Skips the remaining actions of the **current** scope.
    #
    # The context stays successful. Useful inside {Organizer::ClassMethods#iterate}
    # or {Organizer::ClassMethods#reduce_if} to exit the current sub-pipeline
    # without failing. Use {#skip_all_remaining!} to escape outer scopes too.
    #
    # @example
    #   executed do |ctx|
    #     ctx.skip_remaining!("Already paid, skipping invoicing")
    #   end
    #
    # @param message [String, nil] reason for skipping
    # @return [void]
    def skip_remaining!(message = nil)
      @outcome = Success(:message => message)
      @skip_remaining = true
    end

    # Skips every remaining action across all nesting levels.
    #
    # Unlike {#skip_remaining!}, this flag is **never** reset by
    # `ScopedReducable#scoped_reduce`, so it stops even outer scopes.
    #
    # @example
    #   executed do |ctx|
    #     ctx.skip_all_remaining!("Fatal, stop everything")
    #   end
    #
    # @param message [String, nil] reason for skipping
    # @return [void]
    def skip_all_remaining!(message = nil)
      @outcome = Success(:message => message)
      @skip_all_remaining = true
    end

    # Returns `true` when processing should stop for any reason.
    #
    # Combines {#failure?}, {#skip_remaining?} and {#skip_all_remaining?}
    # into a single check. Used by the organizer at every step boundary.
    #
    # @return [Boolean]
    def stop_processing?
      failure? || skip_remaining? || skip_all_remaining?
    end

    # Registers keys as read/write accessors delegated through
    # {#method_missing}.
    #
    # Unlike `define_singleton_method`, this approach does not materialise a
    # singleton class per context instance.
    #
    # @param keys [Array<Symbol>] key names to expose
    # @return [Hash] internal accessor registry
    # @raise [ReservedKeysInContextError] if any key collides with an existing
    #   Hash or Context method
    def define_accessor_methods_for_keys(keys)
      return if keys.nil?

      @accessor_methods ||= {}
      keys.each do |key|
        key = key.to_sym
        next if @accessor_methods.key?(key)

        # Prima il conflitto veniva saltato in silenzio e ctx.size (o :count,
        # :message, ...) ritornava il metodo di Hash invece del valore
        if respond_to?(key) || respond_to?("#{key}=")
          raise ReservedKeysInContextError,
                "expected or promised key :#{key} conflicts with an existing " \
                "#{self.class.name} method: rename the key or access it via ctx[:#{key}]"
        end

        @accessor_methods[key] = [:reader, key]
        @accessor_methods[:"#{key}="] = [:writer, key]
      end
    end

    # Delegates reads and writes to registered accessor keys.
    #
    # When the method name matches a registered key, reads forward to
    # {#fetch} and writes forward to {#[]=}. Otherwise delegates to
    # `Hash#method_missing`.
    #
    # @param name [Symbol] method name
    # @param args [Array] arguments
    # @return [Object, nil]
    def method_missing(name, *args)
      accessor = @accessor_methods && @accessor_methods[name]
      return super unless accessor

      accessor[0] == :reader ? fetch(accessor[1]) : self[accessor[1]] = args.first
    end

    # Returns whether a registered accessor method is available.
    #
    # @param name [Symbol] method name
    # @param _include_all [Boolean] ignored, present for interface
    #   compatibility
    # @return [Boolean]
    def respond_to_missing?(name, _include_all = false)
      (!@accessor_methods.nil? && @accessor_methods.key?(name)) || super
    end

    # Associates one or more alternative key names for existing keys.
    #
    # Both read (`#[]`) and write (`#[]=`) resolve aliases transparently.
    # The assignment `ctx[:alias] = value` writes to the original key,
    # keeping the internal hash free of duplicate entries.
    #
    # @example
    #   ctx.assign_aliases(:codice_fiscale => :cf)
    #   ctx[:cf] = "RSSMRA80A01H501U"
    #   ctx[:codice_fiscale] # => "RSSMRA80A01H501U"
    #
    # @param aliases [Hash{Symbol => Symbol}] maps original keys to alias names
    # @return [self]
    def assign_aliases(aliases)
      @aliases = aliases
      # Hash inverso precomputato: la risoluzione in lettura/scrittura
      # resta O(1) invece del reverse-scan di Hash#key
      @inverse_aliases = aliases.invert

      self
    end

    # Returns the current alias map.
    #
    # @return [Hash{Symbol => Symbol}]
    def aliases
      @aliases ||= {}
    end

    # Reads a value, resolving aliases.
    #
    # @param key [Object] key (converted via {#resolve_key} when aliases
    #   are active)
    # @return [Object, nil]
    def [](key)
      super(resolve_key(key))
    end

    # Writes a value, resolving aliases.
    #
    # When an alias is used as key, the value is stored under the original
    # (canonical) key.
    #
    # @param key [Object] key (converted via {#resolve_key} when aliases
    #   are active)
    # @param value [Object]
    def []=(key, value)
      super(resolve_key(key), value)
    end

    # Reads a value with an optional default, resolving aliases.
    #
    # Follows the standard `Hash#fetch` contract: raises `KeyError` for
    # missing keys when no default is provided, and never writes to the
    # context.
    #
    # @param key [Object] key (converted via {#resolve_key} when aliases
    #   are active)
    # @return [Object] the stored value or the default
    def fetch(key, ...)
      super(resolve_key(key), ...)
    end

    # Checks key presence, resolving aliases.
    #
    # @param key [Object] key (converted via {#resolve_key} when aliases
    #   are active)
    # @return [Boolean]
    def key?(key)
      super(resolve_key(key))
    end

    alias has_key? key?
    alias member? key?
    alias include? key?

    # Returns a human-readable representation of the context.
    #
    # Includes the underlying hash, outcome, error code, skip flags and
    # active aliases.
    #
    # @return [String]
    def inspect
      "#{self.class}(#{self}, success: #{success?}, message: #{check_nil(message)}, error_code: " \
        "#{check_nil(error_code)}, skip_remaining: #{@skip_remaining}, " \
        "skip_all_remaining: #{@skip_all_remaining}, aliases: #{aliases})"
    end

    private

    # Resolves an alias to its canonical key.
    #
    # When no aliases are configured the input key is returned unchanged.
    #
    # @api private
    # @param key [Object] the key to resolve
    # @return [Object] the canonical key
    def resolve_key(key)
      return key unless @inverse_aliases

      @inverse_aliases[key] || key
    end

    # Formats a potentially-nil value for {#inspect}.
    #
    # @api private
    # @param value [Object] the value to format
    # @return [String] `"nil"` when nil, otherwise `"'#{value}'"`
    def check_nil(value)
      return 'nil' unless value

      "'#{value}'"
    end
  end
  # rubocop:enable Metrics/ClassLength
end
