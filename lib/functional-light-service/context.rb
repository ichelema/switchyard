module FunctionalLightService
  # rubocop:disable ClassLength
  class Context < Hash
    include FunctionalLightService::Prelude::Option
    include FunctionalLightService::Prelude::Result
    attr_accessor :outcome, :current_action

    def initialize(context = {},
                   outcome = Success(:message => '', :error => nil))
      @outcome = outcome
      @skip_remaining = false
      context.to_hash.each { |k, v| self[k] = v }
    end

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
      @outcome = Success(:message => '', :error => nil)
      @skip_remaining = false
    end

    def message
      @outcome.value.dig(:message)
    end

    def error_code
      @outcome.value.dig(:error)
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
        error_code = options_or_error_code.delete(:error_code)
        options = options_or_error_code
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
      throw(:jump_when_failed, *args)
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

    def define_accessor_methods_for_keys(keys)
      return if keys.nil?

      keys.each do |key|
        next if respond_to?(key.to_sym)

        define_singleton_method(key.to_s) { fetch(key) }
        define_singleton_method("#{key}=") { |value| self[key] = value }
      end
    end

    def assign_aliases(aliases)
      @aliases = aliases

      aliases.each_pair do |key, key_alias|
        self[key_alias] = self[key]
      end
    end

    def aliases
      @aliases ||= {}
    end

    def [](key)
      key = aliases.key(key) || key
      return super(key)
    end

    def fetch(key, default = nil, &blk)
      self[key] ||= if block_given?
                      super(key, &blk)
                    else
                      super
                    end
    end

    def inspect
      "#{self.class}(#{self}, " \
      + "success: #{success?}, " \
      + "message: #{check_nil(message)}, " \
      + "error_code: #{check_nil(error_code)}, " \
      + "skip_remaining: #{@skip_remaining}, " \
      + "aliases: #{@aliases}" \
      + ")"
    end

    private

    def check_nil(value)
      return 'nil' unless value

      "'#{value}'"
    end
  end
  # rubocop:enable ClassLength
end
