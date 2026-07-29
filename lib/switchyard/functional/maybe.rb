# frozen_string_literal: true

class Object
  def null?
    false
  end

  def some?
    true
  end
end

# rubocop:disable Naming/MethodName
def Maybe(obj)
  Switchyard::Deprecations.warn(
    "Maybe()/Null are deprecated and will be removed in a future release; " \
    "use Switchyard::Option (Some/None) instead"
  )
  obj.nil? ? Null.instance : obj
end
# rubocop:enable Naming/MethodName
