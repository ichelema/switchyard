module FunctionalLightService
  # rubocop:disable Metrics/ClassLength
  class Context < Hash
    include FunctionalLightService::Prelude::Option
    include FunctionalLightService::Prelude::Result
    attr_reader :outcome
    attr_accessor :current_action, :organized_by

    # rubocop:disable Lint/MissingSuper
    def initialize(context = {},
                   outcome = Success(:message => '', :error => nil))
      @outcome = outcome
      @skip_remaining = false
      context.to_hash.each { |k, v| self[k] = v }
    end
    # rubocop:enable Lint/MissingSuper

    def self.make(context = {})
      unless context.is_a?(Hash) || context.is_a?(FunctionalLightService::Context)
        msg = 'Argument must be Hash or FunctionalLightService::Context'
        raise ArgumentError, msg
      end

      context = new(context) unless context.is_a?(Context)

      context.assign_aliases(context.delete(:_aliases)) if context[:_aliases]
      context
    end

    def add_to_context(values)
      merge! values
    end

    def success?
      @outcome.success?
    end

    def failure?
      @outcome.failure?
    end

    def skip_remaining?
      @skip_remaining
    end

    def reset_skip_remaining!
      # Resetta soltanto il flag: l'esito (e il suo messaggio) non vanno persi
      @skip_remaining = false
    end

    def message
      @outcome.value[:message]
    end

    def error_code
      @outcome.value[:error]
    end

    def succeed!(message = nil, options = {})
      message = Configuration.localization_adapter.success(message,
                                                           current_action,
                                                           options)
      @outcome = Success(:message => message)
    end

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

    def fail_and_return!(*args)
      fail!(*args)
      throw(:jump_when_failed)
    end

    def fail_with_rollback!(message = nil, error_code = nil)
      fail!(message, error_code)
      raise FailWithRollbackError
    end

    def skip_remaining!(message = nil)
      @outcome = Success(:message => message)
      @skip_remaining = true
    end

    def stop_processing?
      failure? || skip_remaining?
    end

    # Registra le chiavi come accessor consentiti: la lettura/scrittura passa
    # da method_missing con whitelist. Rispetto a define_singleton_method non
    # materializza una singleton class per ogni context (audit, finding 3.3)
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

    def method_missing(name, *args)
      accessor = @accessor_methods && @accessor_methods[name]
      return super unless accessor

      accessor[0] == :reader ? fetch(accessor[1]) : self[accessor[1]] = args.first
    end

    def respond_to_missing?(name, _include_all = false)
      (!@accessor_methods.nil? && @accessor_methods.key?(name)) || super
    end

    def assign_aliases(aliases)
      @aliases = aliases
      # Hash inverso precomputato: la risoluzione in lettura/scrittura
      # resta O(1) invece del reverse-scan di Hash#key
      @inverse_aliases = aliases.invert

      self
    end

    def aliases
      @aliases ||= {}
    end

    def [](key)
      super(resolve_key(key))
    end

    def []=(key, value)
      super(resolve_key(key), value)
    end

    def fetch(key, *args, &blk)
      super(resolve_key(key), *args, &blk)
    end

    def key?(key)
      super(resolve_key(key))
    end

    alias has_key? key?
    alias member? key?
    alias include? key?

    def inspect
      "#{self.class}(#{self}, success: #{success?}, message: #{check_nil(message)}, error_code: " \
        "#{check_nil(error_code)}, skip_remaining: #{@skip_remaining}, aliases: #{aliases})"
    end

    private

    def resolve_key(key)
      return key unless @inverse_aliases

      @inverse_aliases[key] || key
    end

    def check_nil(value)
      return 'nil' unless value

      "'#{value}'"
    end
  end
  # rubocop:enable Metrics/ClassLength
end
