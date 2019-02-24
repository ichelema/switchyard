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
  obj.nil? ? Null.instance : obj
end
# rubocop:enable Naming/MethodName
