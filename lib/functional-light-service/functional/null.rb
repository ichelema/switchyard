# frozen_string_literal: true

# The simplest NullObject there can be
class Null
  class << self
    def method_missing(m, *args)
      if m == :new
        super
      else
        Null.instance
      end
    end

    def respond_to_missing?(m, _include_all = false)
      m != :new || super
    end

    def instance
      FunctionalLightService::Deprecations.warn(
        "Maybe()/Null are deprecated and will be removed in a future release; " \
        "use FunctionalLightService::Option (Some/None) instead"
      )
      @instance ||= new([])
    end

    def null?
      true
    end

    def some?
      false
    end

    def mimic(klas)
      FunctionalLightService::Deprecations.warn(
        "Maybe()/Null are deprecated and will be removed in a future release; " \
        "use FunctionalLightService::Option (Some/None) instead"
      )
      new(klas.instance_methods(false))
    end

    def ==(other)
      other.respond_to?(:null?) && other.null?
    end
  end
  private_class_method :new

  def initialize(methods)
    @methods = methods
  end

  # implicit conversions
  def to_str
    ''
  end

  def to_ary
    []
  end

  def method_missing(m, *args)
    return self if respond_to_missing?(m)

    super
  end

  def null?
    true
  end

  def some?
    false
  end

  # Convenzione Ruby: si estende respond_to_missing?, mai respond_to?
  # (il vecchio override aveva anche la firma sbagliata: mancava include_all)
  def respond_to_missing?(m, _include_all = false)
    @methods.empty? || @methods.include?(m) || super
  end

  def inspect
    'Null'
  end

  def ==(other)
    other.respond_to?(:null?) && other.null?
  end
end
