# frozen_string_literal: true

require "dry/inflector"

module FunctionalLightService
  module Organizer
    class Iterate
      extend ScopedReducable

      INFLECTOR = Dry::Inflector.new

      def self.run(organizer, collection_key, steps)
        # La singolarizzazione dipende solo dalla chiave: si calcola una volta,
        # non a ogni invocazione dello step (ne' tantomeno per ogni item)
        item_key = INFLECTOR.singularize(collection_key).to_sym

        ->(ctx) do
          return ctx if ctx.stop_processing?

          ctx[collection_key].each do |item|
            ctx[item_key] = item
            ctx = scoped_reduce(organizer, ctx, steps)
          end

          ctx
        end
      end
    end
  end
end
