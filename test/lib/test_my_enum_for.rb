require_relative '../../lib/my_enum_for.rb'
require 'contest'
require 'turn/autorun'

class TestMyEnumFor < Test::Unit::TestCase
  context 'my_enum_for' do
    context 'can be used in iterators which accept 0 or more arguments' do
      test 'with no arguments' do
        def iterator_with_no_arguments
          return my_enum_for(:iterator_with_no_arguments) if !block_given?

          yield 0
        end

        my_enum = iterator_with_no_arguments

        assert_equal 0, my_enum.next
      end

      test 'with 1 argument' do
        def iterator_with_1_argument(arg1)
          return my_enum_for(:iterator_with_1_argument, arg1) if !block_given?

          yield arg1
        end

        my_enum = iterator_with_1_argument(10)

        assert_equal 10, my_enum.next
      end

      test 'with 2 arguments' do
        def iterator_with_2_arguments(arg1, arg2)
          return my_enum_for(:iterator_with_2_arguments, arg1, arg2) if !block_given?

          yield arg1 + arg2
        end

        my_enum = iterator_with_2_arguments(10, 20)

        assert_equal 30, my_enum.next
      end

      test 'with variable number of arguments' do
        def iterator_with_variable_number_of_arguments(*args)
          return my_enum_for(:iterator_with_variable_number_of_arguments, *args) if !block_given?

          yield args.inject(:+)
        end

        args = (1..100).to_a

        my_enum = iterator_with_variable_number_of_arguments(*args)

        assert_equal args.inject(:+), my_enum.next
      end
    end

    context 'returns an enumerator-like object' do
      TOTAL_ITERATIONS = 100

      def iterator(total_iterations)
        return my_enum_for(:iterator, total_iterations) if !block_given?

        total_iterations.times.map do |i|
          yield i ** 2
        end
      end

      def walk_to_end
        loop do
          @my_enum.next
        end
      end

      setup do
        @my_enum = iterator(TOTAL_ITERATIONS)
      end

      test '#next walks forward' do
        TOTAL_ITERATIONS.times do |i|
          assert_equal i ** 2, @my_enum.next
        end
      end

      test '#next raises an exception when walking forward past the last element' do
        walk_to_end

        assert_raise StopIteration do
          @my_enum.next
        end
      end

      test '#previous walks backward' do
        walk_to_end

        # And now go backward, one by one.
        (TOTAL_ITERATIONS - 1).times do |i|
          assert_equal ((TOTAL_ITERATIONS - i - 1) - 1) ** 2, @my_enum.previous
        end
      end

      test '#previous raises an exception when called before traversing the enumerator' do
        assert_raise InvalidEnumeratorIndex do
          @my_enum.previous
        end
      end

      test '#previous raises an exception when walking backward past the 1st element' do
        # Visit 1st element.
        @my_enum.next

        assert_raise StopIteration do
          @my_enum.previous
        end
      end

      test '#first returns the 1st element' do
        assert_equal 0, @my_enum.first
      end

      test '#last returns the last element' do
        assert_equal (TOTAL_ITERATIONS - 1) ** 2, @my_enum.last
      end

      test '#count returns the total number of elements' do
        assert_equal TOTAL_ITERATIONS, @my_enum.count
      end

      test '#[i] returns the ith element, queried in any order' do
        100.times do
          (0..TOTAL_ITERATIONS - 1).to_a.shuffle.each do |i|
            assert_equal i ** 2, @my_enum[i]
          end
        end
      end

      test '#current raises an exception when called before traversing the enumerator' do
        assert_raise InvalidEnumeratorIndex do
          @my_enum.current
        end
      end

      test '#current returns the current element otherwise' do
        TOTAL_ITERATIONS.times do |i|
          @my_enum.next

          assert_equal i ** 2, @my_enum.current
        end
      end

      test '#[i] does not allow negative indices' do
        assert_raise InvalidEnumeratorIndex do
          @my_enum[-1]
        end
      end

      test '#[i] does not allow indices past the last element' do
        assert_raise InvalidEnumeratorIndex do
          @my_enum[@my_enum.count]
        end
      end

      test '#peek returns the next element, but without moving the enumerator forward' do
        TOTAL_ITERATIONS.times do |i|
          10.times { assert_equal i ** 2, @my_enum.peek }

          @my_enum.next
        end
      end

      test '#rewind moves the enumerator to its initial position' do
        walk_to_end
        assert_equal (TOTAL_ITERATIONS - 1) ** 2, @my_enum.current

        @my_enum.rewind
        assert_raise InvalidEnumeratorIndex do
          @my_enum.current
        end
      end

      test 'return value of iterator method is available upon termination' do
        walk_to_end

        assert_equal (0..TOTAL_ITERATIONS - 1).map { |i| [i ** 2] }, @my_enum.return_value
      end
    end
  end
end
