# frozen_string_literal: true

# The simplest NullObject — a do-nothing substitute for any interface.
#
# Requires an explicit `require 'switchyard/functional/maybe'`; not loaded
# by default.
#
# @deprecated Use {Switchyard::Option} instead.
#
class Null
  class << self
    # Forwards any unknown class method to the singleton instance,
    # blocking `:new`.
    #
    # @deprecated
    # @param m [Symbol] method name
    # @param args [Array] arguments
    # @return [Null] the singleton instance
    def method_missing(m, *args)
      if m == :new
        super
      else
        Null.instance
      end
    end

    # @deprecated
    # @param m [Symbol]
    # @param _include_all [Boolean]
    # @return [Boolean]
    def respond_to_missing?(m, _include_all = false)
      m != :new || super
    end

    # Returns the singleton {Null} instance.
    #
    # @deprecated
    # @return [Null]
    def instance
      Switchyard::Deprecations.warn(
        "Maybe()/Null are deprecated and will be removed in a future release; " \
        "use Switchyard::Option (Some/None) instead"
      )
      @instance ||= new([])
    end

    # @deprecated
    # @return [Boolean] always `true`
    def null?
      true
    end

    # @deprecated
    # @return [Boolean] always `false`
    def some?
      false
    end

    # Creates a {Null} that only responds to a specific class's interface.
    #
    # @deprecated
    # @param klas [Class] the class to mimic
    # @return [Null]
    def mimic(klas)
      Switchyard::Deprecations.warn(
        "Maybe()/Null are deprecated and will be removed in a future release; " \
        "use Switchyard::Option (Some/None) instead"
      )
      new(klas.instance_methods(false))
    end

    # @deprecated
    # @param other [Object]
    # @return [Boolean]
    def ==(other)
      other.respond_to?(:null?) && other.null?
    end
  end
  private_class_method :new

  # @param methods [Array<Symbol>] allowed method names
  def initialize(methods)
    @methods = methods
  end

  # @deprecated Implicit string conversion.
  # @return [String] empty string
  def to_str
    ''
  end

  # @deprecated Implicit array conversion.
  # @return [Array] empty array
  def to_ary
    []
  end

  # Forwards unknown methods back to self when the method is in the
  # allowed list.
  #
  # @deprecated
  # @param m [Symbol]
  # @param args [Array]
  # @return [Null]
  def method_missing(m, *args)
    return self if respond_to_missing?(m)

    super
  end

  # @deprecated
  # @return [Boolean] always `true`
  def null?
    true
  end

  # @deprecated
  # @return [Boolean] always `false`
  def some?
    false
  end

  # Uses `respond_to_missing?` (not `respond_to?`) following Ruby
  # convention.
  #
  # @deprecated
  # @param m [Symbol]
  # @param _include_all [Boolean]
  # @return [Boolean]
  def respond_to_missing?(m, _include_all = false)
    @methods.empty? || @methods.include?(m) || super
  end

  # @deprecated
  # @return [String] `"Null"`
  def inspect
    'Null'
  end

  # @deprecated
  # @param other [Object]
  # @return [Boolean]
  def ==(other)
    other.respond_to?(:null?) && other.null?
  end
end
