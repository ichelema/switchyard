# frozen_string_literal: true

require "dry/inflector"

module Switchyard
  module Organizer
    # Iterates over a collection in the context, executing steps per item.
    #
    # For each element of `ctx[collection_key]` the singularised key is
    # set on the context and the steps are run inside a scoped reduce.
    #
    # @example
    #   # Inside an Organizer class:
    #   iterate(:items, [ValidateItem, PriceItem])
    #   # ctx[:item] is set to each element in turn
    #
    class Iterate
      extend ScopedReducable

      # @return [Dry::Inflector] used to singularise the collection key
      INFLECTOR = Dry::Inflector.new

      # Builds a lambda that iterates the collection.
      #
      # The singular form of `collection_key` is computed once when the
      # step is defined, not on every invocation.
      #
      # @param organizer [Module] the owning organizer
      # @param collection_key [Symbol] context key holding the enumerable
      # @param steps [Array<Class, Proc>] actions per item
      # @return [Proc] callable step
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
