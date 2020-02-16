require "dry/inflector"

module FunctionalLightService
  module Organizer
    class Iterate
      extend ScopedReducable

      def self.run(organizer, collection_key, steps)
        ->(ctx) do
          return ctx if ctx.stop_processing?

          collection = ctx[collection_key]
          inflector = Dry::Inflector.new
          item_key = inflector.singularize(collection_key).to_sym
          collection.each do |item|
            ctx[item_key] = item
            ctx = scoped_reduce(organizer, ctx, steps)
          end

          ctx
        end
      end
    end
  end
end
