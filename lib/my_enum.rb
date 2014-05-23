class MyEnumerator
  attr_reader :method, :method_args, :cache

  def initialize(method, *method_args)
    @method      = method
    @method_args = method_args
    @cache       = []
  end

  def next
    if cache.empty?
      fiber.resume
    else
      cache.shift
    end
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
    @cache = []
  end

  def count
    previous_state = [fiber, cache]
    rewind

    item_count = 0
    loop do
      self.next   # Remember: 'next' is a reserved word. Use 'self.next' instead!
      item_count += 1
    end

    @fiber, @cache = previous_state

    item_count
  end

  def peek
    cache << self.next if cache.empty?

    cache.first
  end
end

module Kernel
  def my_enum_for(method_name, *args)
    MyEnumerator.new method(method_name), *args
  end
end
