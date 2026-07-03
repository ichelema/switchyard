# frozen_string_literal: true

module FunctionalLightService
  module Enum
    class MatchError < StandardError; end
  end

  class EnumBuilder
    def initialize(parent)
      @parent = parent
    end

    class DataType
      module AnyEnum
        include FunctionalLightService::Monad

        def match(&)
          parent.match(self, &)
        end

        def to_s
          value.to_s
        end

        def name
          self.class.name.split("::")[-1]
        end

        # Returns array. Will fail on Nullary objects.
        # TODO: define a Unary module so we can define this method differently on Unary vs Binary
        def wrapped_values
          if is_a?(FunctionalLightService::EnumBuilder::DataType::Binary)
            value.values
          else
            [value]
          end
        end

        # Supporto al pattern matching nativo di Ruby (case/in):
        #   case result
        #   in FunctionalLightService::Result::Success(s) then ...
        #   in FunctionalLightService::Result::Failure(f) then ...
        #   end
        def deconstruct
          is_a?(FunctionalLightService::EnumBuilder::DataType::Nullary) ? [] : wrapped_values
        end

        def deconstruct_keys(_keys)
          if is_a?(FunctionalLightService::EnumBuilder::DataType::Binary)
            value.dup
          elsif is_a?(FunctionalLightService::EnumBuilder::DataType::Nullary)
            {}
          else
            { args[0] => value }
          end
        end
      end

      module Nullary
        def initialize(*_args)
          @value = nil
        end

        def inspect
          name
        end
      end

      # TODO: this should probably be named Multary
      module Binary
        def initialize(*init)
          unless (init.one? && init[0].is_a?(Hash)) || init.count == args.count
            raise ArgumentError, "Expected arguments for #{args}, got #{init}"
          end

          @value = if init.one? && init[0].is_a?(Hash)
                     args.zip(init[0].values).to_h
                   else
                     args.zip(init).to_h
                   end
        end

        def inspect
          params = value.map { |k, v| "#{k}: #{v.inspect}" }
          "#{name}(#{params.join(', ')})"
        end
      end

      # rubocop:disable Metrics/MethodLength
      def self.create(parent, args)
        if args.include? :value
          raise ArgumentError, "#{args} may not contain the reserved name :value"
        end

        dt = Class.new(parent)

        dt.instance_eval do
          public_class_method :new
          include AnyEnum

          define_method(:args) { args }

          define_method(:parent) { parent }
          private :parent
        end

        case args.count
        when 0
          dt.instance_eval do
            include Nullary

            private :value
          end
        when 1
          dt.instance_eval do
            define_method(args[0].to_sym) { value }
          end
        else
          dt.instance_eval do
            include Binary

            args.each do |m|
              define_method(m) do
                @value[m]
              end
            end
          end
        end

        dt
      end
      # rubocop:enable Metrics/MethodLength

      class << self
        public :new
      end
    end

    def method_missing(m, *args)
      if @parent.const_defined?(m)
        raise ArgumentError, "variant #{m} is already defined for this enum"
      end

      @parent.const_set(m, DataType.create(@parent, args))
    end

    def respond_to_missing?(_m, _include_all = false)
      true
    end
  end

  module_function

  # rubocop:disable Metrics/AbcSize
  # rubocop:disable Metrics/CyclomaticComplexity
  # rubocop:disable Metrics/MethodLength
  # rubocop:disable Metrics/PerceivedComplexity
  def enum(&block)
    mod = Class.new do # the enum to be built
      private_class_method :new

      def self.match(obj, &block)
        # Binding#receiver: stesso risultato di binding.eval('self') senza eval
        caller_ctx = block.binding.receiver

        matcher = self::Matcher.new(obj)
        matcher.instance_eval(&block)

        # exhaustiveness check su classi memoizzate: niente split/sort di
        # stringhe per chiamata
        covered = matcher.matches.map { |e| e[1] }
        missing = variant_classes.reject { |klass| covered.include?(klass) }
        unless missing.empty?
          missing_names = missing.map { |klass| klass.name.split('::')[-1].to_sym }
          raise Enum::MatchError, "Match is non-exhaustive, #{missing_names} not covered"
        end

        type_matches = matcher.matches.select { |r| r[0].is_a?(r[1]) }

        type_matches.each do |match|
          obj, _type, block, args, guard = match

          return caller_ctx.instance_eval(&block) if args.empty?

          if args.count != obj.args.count
            msg = "Pattern (#{args.join(', ')}) must match (#{obj.args.join(', ')})"
            raise Enum::MatchError, msg
          end

          guard_ctx = guard_context(obj, args)
          return caller_ctx.instance_exec(* obj.wrapped_values, &block) unless guard

          if guard && guard_ctx.instance_exec(obj, &guard)
            return caller_ctx.instance_exec(* obj.wrapped_values, &block)
          end
        end

        raise Enum::MatchError, "No match could be made"
      end

      def self.variants
        constants - %i[Matcher MatchError]
      end

      def self.variant_classes
        @variant_classes ||= variants.map { |v| const_get(v) }.freeze
      end

      def self.guard_context(obj, args)
        # Struct.new definisce una classe: va fatto una volta per firma,
        # non a ogni match con guard
        @guard_structs ||= {}
        struct = @guard_structs[args] ||= Struct.new(*args)

        if obj.is_a?(FunctionalLightService::EnumBuilder::DataType::Binary)
          struct.new(*obj.value.values)
        else
          struct.new(obj.value)
        end
      end
    end
    enum = EnumBuilder.new(mod)
    enum.instance_eval(&block)

    type_variants = mod.constants

    matcher = Class.new do
      def initialize(obj)
        @obj = obj
        @matches = []
        @vars = []
      end

      attr_reader :matches, :vars

      def where(&guard)
        guard
      end

      type_variants.each do |m|
        define_method(m) do |guard = nil, &inner_block|
          raise ArgumentError, "No block given to `#{m}`" if inner_block.nil?

          params_spec = inner_block.parameters
          if params_spec.any? { |spec| spec.size < 2 }
            msg = "Unnamed param found in block parameters: #{params_spec.inspect}"
            raise ArgumentError, msg
          end
          if params_spec.any? { |spec| spec[0] != :req && spec[0] != :opt }
            msg = "Only :req & :opt params allowed; parameters=#{params_spec.inspect}"
            raise ArgumentError, msg
          end

          args = params_spec.map { |spec| spec[1] }

          type = mod.const_get(m)

          guard = nil if guard && !guard.is_a?(Proc)

          @matches << [@obj, type, inner_block, args, guard]
        end
      end
    end

    mod.const_set(:Matcher, matcher)

    type_variants.each do |variant|
      mod.singleton_class.class_exec do
        define_method(variant) do |*args|
          const_get(variant).new(*args)
        end
      end
    end
    mod
  end
  # rubocop:enable Metrics/AbcSize
  # rubocop:enable Metrics/CyclomaticComplexity
  # rubocop:enable Metrics/MethodLength
  # rubocop:enable Metrics/PerceivedComplexity

  def impl(enum_type, &block)
    enum_type.variants.each do |v|
      enum_type.const_get(v).class_eval(&block)
    end
  end
end
