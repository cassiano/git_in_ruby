require File.join(File.dirname(File.expand_path(__FILE__)), '../head_fsck')
require 'contest'
require 'turn/autorun'

class TestFsck < Test::Unit::TestCase
  setup do
    @git_repositories_folder = File.join(File.dirname(File.expand_path(__FILE__)), 'git_repositories/')
  end

  test 'checks for invalid mode' do
    assert_raise InvalidModeError do
      head_fsck File.join(@git_repositories_folder, 'invalid_mode')
    end
  end

  test 'checks for invalid SHA1' do
    assert_raise InvalidSha1Error do
      head_fsck File.join(@git_repositories_folder, 'invalid_sha1')
    end
  end

  test 'checks for invalid size' do
    assert_raise InvalidSizeError do
      head_fsck File.join(@git_repositories_folder, 'invalid_size')
    end
  end

  test 'checks for invalid type' do
    assert_raise InvalidTypeError do
      head_fsck File.join(@git_repositories_folder, 'invalid_type')
    end
  end

  test 'checks for missing tree in commit' do
    assert_raise MissingTreeInCommitError do
      head_fsck File.join(@git_repositories_folder, 'missing_tree_in_commit')
    end
  end

  test 'checks for missing object' do
    assert_raise MissingObjectError do
      head_fsck File.join(@git_repositories_folder, 'missing_object')
    end
  end
end
