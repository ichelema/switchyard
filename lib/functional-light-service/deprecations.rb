module FunctionalLightService
  # Deprecation warnings non fatali: ogni messaggio viene emesso una sola
  # volta per processo (su stderr) e puo' essere silenziato globalmente,
  # ad esempio nelle suite di test.
  module Deprecations
    @emitted = {}

    class << self
      attr_accessor :silenced

      def warn(message)
        return if silenced
        return if @emitted[message]

        @emitted[message] = true
        Kernel.warn("DEPRECATION WARNING: #{message}")
      end

      def reset!
        @emitted = {}
      end
    end
  end
end
