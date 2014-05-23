class MyEnumerator
  attr_reader :method, :args

  def initialize(method, *args)
    @method = method
    @args   = args
  end

  def next
    fiber.resume
  end

  def fiber
    @fiber ||= Fiber.new do
      method.call(*args) do |*args2|
        Fiber.yield *args2
      end

      raise StopIteration, 'iteration reached an end'
    end
  end

  def rewind
    @fiber = nil
  end

  def count
    previous_fiber = fiber
    rewind

    item_count = 0
    loop do
      self.next   # Remember: 'next' is a reserved word. Use 'self.next' instead!
      item_count += 1
    end

    @fiber = previous_fiber

    item_count
  end
end

class Object
  def my_enum_for(method_name, *args)
    MyEnumerator.new method(method_name), *args
  end
end
