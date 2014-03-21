require File.join(File.dirname(File.expand_path(__FILE__)), '../fsck')
require 'contest'
require 'turn/autorun'

class TestFsck < Test::Unit::TestCase
  test 'checks for invalid mode' do
    assert_raise InvalidModeError do
      fsck File.join(File.dirname(File.expand_path(__FILE__)), 'git_repositories/invalid_mode')
    end
  end

  test 'checks for invalid SHA1' do
    assert_raise InvalidSha1Error do
      fsck File.join(File.dirname(File.expand_path(__FILE__)), 'git_repositories/invalid_sha1')
    end
  end

  test 'checks for invalid size' do
    assert_raise InvalidSizeError do
      fsck File.join(File.dirname(File.expand_path(__FILE__)), 'git_repositories/invalid_size')
    end
  end

  test 'checks for invalid type' do
    assert_raise InvalidTypeError do
      fsck File.join(File.dirname(File.expand_path(__FILE__)), 'git_repositories/invalid_type')
    end
  end

  test 'checks for missing object' do
    assert_raise MissingObjectError do
      fsck File.join(File.dirname(File.expand_path(__FILE__)), 'git_repositories/missing_object')
    end
  end

  test 'checks for missing tree in commit' do
    assert_raise MissingTreeInCommitError do
      fsck File.join(File.dirname(File.expand_path(__FILE__)), 'git_repositories/missing_tree_in_commit')
    end
  end
end
