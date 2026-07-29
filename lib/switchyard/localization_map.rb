# frozen_string_literal: true

require 'singleton'

module Switchyard
  class LocalizationMap < Hash
    include ::Singleton
  end
end
