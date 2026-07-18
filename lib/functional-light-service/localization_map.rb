# frozen_string_literal: true

require 'singleton'

module FunctionalLightService
  class LocalizationMap < Hash
    include ::Singleton
  end
end
