class AssertionError < RuntimeError
end

class Object
  def assert
    raise AssertionError unless yield
  end
end
