# frozen_string_literal: true

module Switchyard
  # Non-fatal deprecation warnings, emitted at most once per process.
  #
  # Deprecations warn on `stderr` the first time a deprecated API is used
  # and stay silent on subsequent calls. Warnings can be silenced globally
  # (e.g. in test suites) and re-enabled by clearing the emission history.
  #
  # @example
  #   Switchyard::Deprecations.warn("Maybe() is deprecated; use Option instead")
  #
  # @example Silencing in a test suite
  #   Switchyard::Deprecations.silenced = true
  #
  # @example Resetting for isolated tests
  #   Switchyard::Deprecations.reset!
  #
  module Deprecations
    @emitted = {}

    class << self
      # When `true` every call to {.warn} is a no-op.
      #
      # @return [Boolean]
      attr_accessor :silenced

      # Emits a deprecation warning on `stderr`, once per message.
      #
      # Subsequent calls with the same message string are silently dropped
      # unless {.reset!} has been called in between.
      #
      # @param message [String] the deprecation message to display
      # @return [void]
      def warn(message)
        return if silenced
        return if @emitted[message]

        @emitted[message] = true
        Kernel.warn("DEPRECATION WARNING: #{message}")
      end

      # Clears the set of already-emitted messages.
      #
      # Call this between tests to ensure each spec can observe the warning
      # independently.
      #
      # @return [void]
      def reset!
        @emitted = {}
      end
    end
  end
end
