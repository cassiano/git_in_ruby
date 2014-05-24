 require 'fiber'

 class MyEnumerator
  attr_reader :method, :method_args, :cache

  def initialize(method, *method_args)
    @method      = method
    @method_args = method_args

    reset_cache
  end

  def next
    if next_value_not_in_cache?
      if fiber.alive?
        fiber.resume.tap do |value|
          add_to_cache value
        end
      else
        raise StopIteration, 'iteration reached an end'
      end
    else
      cache[:current_index] += 1

      current_cache_value
    end
  end

  def previous
    raise StopIteration, 'iteration reached an end' if cache[:current_index] == -1

    cache[:current_index] -= 1

    current_cache_value
  end

  def current
    current_cache_value
  end

  def count
    saved_cache_index = cache[:current_index]
    rewind

    item_count = 0
    loop do
      self.next   # Remember: 'next' is a reserved word. Use 'self.next' instead!
      item_count += 1
    end

    cache[:current_index] = saved_cache_index

    item_count
  end

  def peek
    if next_value_not_in_cache?
      self.next
      cache[:current_index] -= 1
    end

    cache[:data][ cache[:current_index] + 1 ]
  end

  def rewind
    reset_cache_index
    nil
  end

  def first
    rewind
    self.next
  end

  def last
    loop do
      self.next
    end

    current
  end

  private

  def fiber
    @fiber ||= Fiber.new do
      method.call(*method_args) do |*args|
        Fiber.yield *args
      end

      raise StopIteration, 'iteration reached an end'
    end
  end

  def add_to_cache(value)
    cache[:current_index] += 1

    cache[:data][ cache[:current_index] ] = value
  end

  def reset_cache
    @cache ||= {}

    cache[:data] = []

    reset_cache_index
  end

  def reset_cache_index
    cache[:current_index] = -1
  end

  def current_cache_value
    return nil if cache[:current_index] == -1

    cache[:data][ cache[:current_index] ]
  end

  def next_value_not_in_cache?
    cache[:current_index] + 1 > cache[:data].count - 1
  end
end

module Kernel
  def my_enum_for(method_name, *args)
    MyEnumerator.new method(method_name), *args
  end
end
