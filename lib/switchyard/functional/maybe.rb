# frozen_string_literal: true

# Object extension for {Null} compatibility (opt-in).
#
# Requires `require 'switchyard/functional/maybe'` explicitly; this is
# not loaded by default.
#
# @deprecated Use {Switchyard::Option} instead.
#
# @example
#   require 'switchyard/functional/maybe'
#   Maybe(nil)  # => Null.instance
#   Maybe(42)   # => 42
#   Maybe(42).some?  # => true
#
class Object
  # @deprecated
  # @return [Boolean] always `false`
  def null?
    false
  end

  # @deprecated
  # @return [Boolean] always `true`
  def some?
    true
  end
end

# rubocop:disable Naming/MethodName
# Wraps a potentially-nil value, returning {Null.instance} when nil.
#
# @deprecated Use {Switchyard::Option.some?} instead.
# @param obj [Object] the value to wrap
# @return [Object, Null] the value itself or {Null.instance}
def Maybe(obj)
  Switchyard::Deprecations.warn(
    "Maybe()/Null are deprecated and will be removed in a future release; " \
    "use Switchyard::Option (Some/None) instead"
  )
  obj.nil? ? Null.instance : obj
end
# rubocop:enable Naming/MethodName
