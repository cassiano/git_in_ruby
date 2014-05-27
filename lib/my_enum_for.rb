require 'fiber'

class InvalidMyEnumeratorIndex < StandardError; end

class MyEnumerator
  attr_reader :method, :method_args, :cache, :result
  attr_accessor :cache_index

  def initialize(method, *method_args)
    @method      = method
    @method_args = method_args
    @result      = nil

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
      inc_cache_index
      current_cache_value
    end
  end

  def previous
    raise StopIteration, 'iteration reached an end' if !valid_cache_index?

    dec_cache_index
    current_cache_value
  end

  def current
    current_cache_value
  end

  def count
    # Save the current cache index.
    saved_cache_index = cache_index

    rewind

    item_count = 0

    loop do
      self.next   # Remember: 'next' is a reserved word. Use 'self.next' instead!

      item_count += 1
    end

    # Restore the previous cache index.
    self.cache_index = saved_cache_index

    item_count
  end

  def peek
    if !next_value_in_cache?
      self.next
      dec_cache_index
    end

    cache[cache_index + 1]
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
      if index < cache.count
        self.cache_index = index
      else
        # Position the (cache) index at the last cached element.
        self.cache_index = cache.count - 1

        # Walk the remaining elements.
        (index - cache.count + 1).times do
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
      @result = method.call(*method_args) do |*args|
        args.tap do
          Fiber.yield *args
        end
      end

      raise StopIteration, 'iteration reached an end'
    end
  end

  def add_to_cache(value)
    inc_cache_index

    cache[cache_index] = value
  end

  def initialize_or_reset_cache
    @cache = []

    reset_cache_index
  end

  def reset_cache_index
    self.cache_index = -1
  end

  def inc_cache_index
    self.cache_index += 1
  end

  def dec_cache_index
    self.cache_index -= 1
  end

  def valid_cache_index?
    cache_index != -1
  end

  def current_cache_value
    cache[cache_index] if valid_cache_index?
  end

  def next_value_in_cache?
    cache_index + 1 <= cache.count - 1
  end
end

module Kernel
  def my_enum_for(method_name, *args)
    MyEnumerator.new method(method_name), *args
  end
end
