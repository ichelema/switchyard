# frozen_string_literal: true

module Switchyard
  # Pattern-matching support for enum variants.
  module Enum
    # Raised by {EnumBuilder::DataType::AnyEnum#match} when not all variants are covered or no
    # guard matches.
    class MatchError < StandardError; end
  end

  # Builds algebraic data types (enums with variants).
  #
  # Each variant is a class under the enum module. Variants may carry
  # positional arguments (`:s`), multiple named arguments (`:a, :b`),
  # or no arguments (nullary).
  #
  # @example
  #   Shape = Switchyard.enum do
  #     Circle(:radius)
  #     Rect(:width, :height)
  #     Point()
  #   end
  #
  # @see Switchyard.enum
  # @see Switchyard.impl
  class EnumBuilder
    # @param parent [Class] the enum module being built
    def initialize(parent)
      @parent = parent
    end

    # Base type for all enum variant instances.
    class DataType
      # Shared behaviour for every variant instance.
      module AnyEnum
        include Switchyard::Monad

        # Pattern matches this variant against the cases in the block.
        #
        # Uses the enum's generated `Matcher` class to dispatch.
        #
        # @yield a block with case clauses (variant names)
        # @return [Object] the matched block's return value
        # @raise [Enum::MatchError] when no variant matches
        def match(&)
          parent.match(self, &)
        end

        # Returns the string representation of the inner value.
        #
        # @return [String]
        def to_s
          value.to_s
        end

        # Returns the short name of this variant (e.g. `"Success"`).
        #
        # @return [String]
        def name
          self.class.name.split("::")[-1]
        end

        # Returns the wrapped values for destructuring.
        #
        # For binary variants, returns the hash values; for unary,
        # returns an array with the single value.
        #
        # @return [Array]
        def wrapped_values
          if is_a?(Switchyard::EnumBuilder::DataType::Binary)
            value.values
          else
            [value]
          end
        end

        # Native Ruby pattern-matching support (`case`/`in`).
        #
        # @example
        #   case result
        #   in Switchyard::Result::Success(s) then s
        #   in Switchyard::Result::Failure(f) then handle(f)
        #   end
        #
        # @return [Array] the wrapped values for destructuring
        def deconstruct
          is_a?(Switchyard::EnumBuilder::DataType::Nullary) ? [] : wrapped_values
        end

        # Native Ruby pattern-matching for keyword destructuring.
        #
        # @param _keys [nil] ignored
        # @return [Hash] variant data keyed by argument names
        def deconstruct_keys(_keys)
          if is_a?(Switchyard::EnumBuilder::DataType::Binary)
            value.dup
          elsif is_a?(Switchyard::EnumBuilder::DataType::Nullary)
            {}
          else
            { args[0] => value }
          end
        end
      end

      # Behaviour for variants that carry no value (e.g. `None`).
      module Nullary
        # @param _args [Array] ignored
        def initialize(*_args)
          @value = nil
        end

        # @return [String] the variant name only
        def inspect
          name
        end
      end

      # Behaviour for variants with multiple named arguments.
      # @see Binary#initialize Binary for constructor details
      module Binary
        # Initialises a Binary variant from positional or hash arguments.
        #
        # Accepts either positional values matching the declared argument
        # names, or a single hash whose keys match the argument names.
        #
        # @param init [Array, Hash] values for the named arguments
        # @raise [ArgumentError] if the number of arguments does not match
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

        # Returns a human-readable representation.
        #
        # @example
        #   Rect(width: 10, height: 20).inspect  # => "Rect(width: 10, height: 20)"
        #
        # @return [String]
        def inspect
          params = value.map { |k, v| "#{k}: #{v.inspect}" }
          "#{name}(#{params.join(', ')})"
        end
      end

      # Creates an enum variant class.
      #
      # The generated class includes {AnyEnum} and the appropriate
      # mixin ({Nullary} for 0-arg, unary for 1-arg, {Binary} for 2+).
      #
      # @param parent [Class] the enum module
      # @param args [Array<Symbol>] argument names
      # @return [Class] the variant class
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

    # Defines a new variant on the enum.
    #
    # Variant names become constants under the enum module. Each variant
    # declares its positional argument names.
    #
    # @example
    #   my_enum.Rect(:width, :height)  # defines Rect(width:, height:)
    #
    # @param m [Symbol] variant name
    # @param args [Array<Symbol>] argument names
    # @return [void]
    # @raise [ArgumentError] if the variant was already defined
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
  # Creates a new algebraic data type (enum).
  #
  # Returns a class with variant subclasses, each with its own
  # constructor, `#inspect`, `#match` and native Ruby `case`/`in`
  # support.
  #
  # @example
  #   Status = Switchyard.enum do
  #     Active(:user)
  #     Inactive()
  #   end
  #
  # @yield block in which variant names are called as methods
  # @return [Class] the enum class
  def enum(&block)
    mod = Class.new do # the enum to be built
      private_class_method :new

      def self.match(obj, &block)
        # Binding#receiver: same result as binding.eval('self') without eval
        caller_ctx = block.binding.receiver

        matcher = self::Matcher.new(obj)
        matcher.instance_eval(&block)

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
        # Struct.new defines a class: do it once per signature,
        # not on every guarded match
        @guard_structs ||= {}
        struct = @guard_structs[args] ||= Struct.new(*args)

        if obj.is_a?(Switchyard::EnumBuilder::DataType::Binary)
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

  # Evaluates a block in the context of every variant class of an enum.
  #
  # Used to define shared methods (like `map`, `fmap`, `value_or`) on
  # all variants at once.
  #
  # @example
  #   Switchyard.impl(Option) do
  #     def some?; is_a? Option::Some; end
  #   end
  #
  # @param enum_type [Class] the enum class (returned by {.enum})
  # @yield block evaluated in each variant class
  # @return [void]
  def impl(enum_type, &block)
    enum_type.variants.each do |v|
      enum_type.const_get(v).class_eval(&block)
    end
  end
end
