# frozen_string_literal: true

require 'singleton'

module Switchyard
  # Singleton hash for message localisation data.
  #
  # Populated by host applications with locale-scoped message strings.
  # Used by {LocalizationAdapter} for symbol-based message lookups.
  #
  # @example
  #   Switchyard::LocalizationMap.instance[:en][:my_action][:switchyard][:successes][:done] = "Done"
  #
  class LocalizationMap < Hash
    include ::Singleton
  end
end
