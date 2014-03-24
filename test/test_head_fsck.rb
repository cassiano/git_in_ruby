require File.join(File.dirname(File.expand_path(__FILE__)), '../head_fsck')
require 'contest'
require 'turn/autorun'

class TestFsck < Test::Unit::TestCase
  setup do
    @git_repositories_folder = File.join(File.dirname(File.expand_path(__FILE__)), 'git_repositories')
  end

  test 'checks for invalid mode' do
    assert_raise InvalidModeError do
      repository = GitRepository.new(File.join(@git_repositories_folder, 'invalid_mode'))
      repository.head_fsck!
    end
  end

  test 'checks for invalid SHA1' do
    exception = assert_raise InvalidSha1Error do
      repository = GitRepository.new(File.join(@git_repositories_folder, 'invalid_sha1'))
      repository.head_fsck!
    end

    assert_match "Invalid SHA1 '3de30b238598c23f462df3a5e470f85dab97b195' (expected 'fcdaaf078251cd016aa65debc46c9ada14c0e2fe')", exception.message
  end

  test 'checks for invalid size' do
    assert_raise InvalidSizeError do
      repository = GitRepository.new(File.join(@git_repositories_folder, 'invalid_size'))
      repository.head_fsck!
    end
  end

  test 'checks for invalid type' do
    assert_raise InvalidTypeError do
      repository = GitRepository.new(File.join(@git_repositories_folder, 'invalid_type'))
      repository.head_fsck!
    end
  end

  test 'checks for missing tree in commit' do
    exception = assert_raise MissingCommitDataError do
      repository = GitRepository.new(File.join(@git_repositories_folder, 'missing_tree_in_commit'))
      repository.head_fsck!
    end

    assert_match "Missing tree in commit", exception.message
  end

  # test 'checks for missing object' do
  #   exception = assert_raise MissingObjectError do
  #     repository = GitRepository.new(File.join(@git_repositories_folder, 'missing_object'))
  #     repository.head_fsck!
  #   end
  #
  #   assert_match %r(File '.*/\.git/objects/bd/9dbf5aae1a3862dd1526723246b20206e5fc37' not found), exception.message
  # end
end
