class MyEnumerator
  attr_reader :method, :method_args

  def initialize(method, *method_args)
    @method      = method
    @method_args = method_args
  end

  def next
    fiber.resume
  end

  def fiber
    @fiber ||= Fiber.new do
      method.call(*method_args) do |*args|
        Fiber.yield *args
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

module Kernel
  def my_enum_for(method_name, *args)
    MyEnumerator.new method(method_name), *args
  end
end
