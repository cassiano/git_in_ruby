require_relative '../../lib/my_enum.rb'
require 'contest'
require 'turn/autorun'

class TestMyEnum < Test::Unit::TestCase
  def iterator(*args)
    return my_enum_for(:iterator, *args) if !block_given?

    yield 1 + args[0]
    yield 2 + args[1]
    yield 3 + args[2]
  end

  context 'my_enum_for returns an enumerator-like object' do
    setup do
      @my_enum = iterator(10, 20, 30)
    end

    test '#next walks forward' do
      assert_equal 11, @my_enum.next
      assert_equal 22, @my_enum.next
      assert_equal 33, @my_enum.next
    end

    test '#previous walks backward' do
      loop { @my_enum.next }

      assert_equal 22, @my_enum.previous
      assert_equal 11, @my_enum.previous
    end

    test '#first and #last return the 1st and last elements, respectively' do
      assert_equal 11, @my_enum.first
      assert_equal 33, @my_enum.last
    end

    test '#count returns the total # of elements' do
      assert_equal 3, @my_enum.count
    end

    test '#[n] returns nth element' do
      0.upto(2).each do |n|
        assert_equal (n + 1) * 11, @my_enum[n]
      end
    end

    test '#current returns the current element' do
      3.times do |n|
        @my_enum.next

        assert_equal (n + 1) * 11, @my_enum.current
      end
    end

    test '#peek returns the next element, but without moving the enumerator forward' do
      3.times do |n|
        10.times { assert_equal (n + 1) * 11, @my_enum.peek }

        @my_enum.next
      end
    end

    test '#rewind walks backward all the way, moving the enumerator to its initial position' do
      loop { @my_enum.next }
      assert_equal 33, @my_enum.current

      @my_enum.rewind
      assert_equal nil, @my_enum.current

      @my_enum.next
      assert_equal 11, @my_enum.current
    end
  end
end
