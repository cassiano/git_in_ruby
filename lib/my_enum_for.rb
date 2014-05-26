require 'fiber'

class InvalidMyEnumeratorIndex < StandardError; end

class MyEnumerator
  attr_reader :method, :method_args, :cache

  def initialize(method, *method_args)
    @method      = method
    @method_args = method_args
    @cache       = {}

    initialize_or_reset_cache
  end

  def next
    if !next_value_in_cache?
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
    raise StopIteration, 'iteration reached an end' if !valid_cache_index?

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
    if !next_value_in_cache?
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

  def [](index)
    raise InvalidMyEnumeratorIndex, 'negative indices not allowed' unless index >= 0

    begin
      if index < cache[:data].count
        cache[:current_index] = index
      else
        # Position the (cache) index at the last cached element.
        cache[:current_index] = cache[:data].count - 1

        # Walk the remaining elements.
        (index - cache[:data].count + 1).times do
          self.next
        end
      end

      current
    rescue StopIteration
      raise InvalidMyEnumeratorIndex, 'maximum allowed index exceeded'
    end
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

  def initialize_or_reset_cache
    cache[:data] = []

    reset_cache_index
  end

  def reset_cache_index
    cache[:current_index] = -1
  end

  def valid_cache_index?
    cache[:current_index] != -1
  end

  def current_cache_value
    return nil if !valid_cache_index?

    cache[:data][ cache[:current_index] ]
  end

  def next_value_in_cache?
    cache[:current_index] + 1 <= cache[:data].count - 1
  end
end

module Kernel
  def my_enum_for(method_name, *args)
    MyEnumerator.new method(method_name), *args
  end
end
