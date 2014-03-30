require File.join(File.dirname(File.expand_path(__FILE__)), '../head_fsck')
require 'contest'
require 'turn/autorun'

class TestFsck < Test::Unit::TestCase
  setup do
    @git_repositories_folder = File.join(File.dirname(File.expand_path(__FILE__)), 'git_repositories')
  end

  context 'FileSystemGitRepository' do
    context '#create_commit!' do
      setup do
        @author_and_committer = 'Cassiano D Andrea <cassiano.dandrea@tagview.com.br>'
      end

      test 'creates a valid commit object with no parent' do
        repository = FileSystemGitRepository.new(project_path: File.join(@git_repositories_folder, 'dynamic'))

        blob1 = repository.create_blob!('blob1 content')
        blob2 = repository.create_blob!('blob2 content')

        tree1 = repository.create_tree!([
          [:blob, 'file1', blob1]
        ])
        tree2 = repository.create_tree!([
          [:blob, 'file2',    blob2],
          [:tree, 'folder1',  tree1]
        ])

        commit = repository.create_commit!('master', tree2, [], @author_and_committer, @author_and_committer, "1st commit")

        assert_equal commit, repository.head_commit.sha1
        assert_equal [], repository.head_commit.parents
        assert_equal tree2, repository.head_commit.tree.sha1
        assert_equal tree1, repository.head_commit.tree.entries['folder1'].sha1

        assert_nothing_raised do
          repository.head_fsck
        end
      end
    end

    context '#head_fsck' do
      test 'checks for invalid mode' do
        assert_raise InvalidModeError do
          repository = FileSystemGitRepository.new(project_path: File.join(@git_repositories_folder, 'invalid_mode'))
          repository.head_fsck
        end
      end

      test 'checks for invalid SHA1' do
        exception = assert_raise InvalidSha1Error do
          repository = FileSystemGitRepository.new(project_path: File.join(@git_repositories_folder, 'invalid_sha1'))
          repository.head_fsck
        end

        assert_match "Invalid SHA1 '3de30b238598c23f462df3a5e470f85dab97b195' (expected 'fcdaaf078251cd016aa65debc46c9ada14c0e2fe')", exception.message
      end

      test 'checks for invalid size' do
        assert_raise InvalidSizeError do
          repository = FileSystemGitRepository.new(project_path: File.join(@git_repositories_folder, 'invalid_size'))
          repository.head_fsck
        end
      end

      test 'checks for invalid type' do
        assert_raise InvalidTypeError do
          repository = FileSystemGitRepository.new(project_path: File.join(@git_repositories_folder, 'invalid_type'))
          repository.head_fsck
        end
      end

      test 'checks for missing tree in commit' do
        exception = assert_raise MissingCommitDataError do
          repository = FileSystemGitRepository.new(project_path: File.join(@git_repositories_folder, 'missing_tree_in_commit'))
          repository.head_fsck
        end

        assert_match "Missing tree in commit", exception.message
      end

      test 'checks for missing object' do
        exception = assert_raise MissingObjectError do
          repository = FileSystemGitRepository.new(project_path: File.join(@git_repositories_folder, 'missing_object'))
          repository.head_fsck
        end

        assert_match %r(File '.*/\.git/objects/bd/9dbf5aae1a3862dd1526723246b20206e5fc37' not found), exception.message
      end
    end
  end

  context 'Commit' do
    context '#changes_introduced_by' do
      test 'shows additions, deletions or changes with no parent' do
        repository = FileSystemGitRepository.new(project_path: File.join(@git_repositories_folder, 'valid_with_merge'))
        commit     = Commit.find_or_initialize_by_sha1(repository, 'f9cc0ed357a451a0d7a4b429209f7e80a6f83240')

        assert_equal [
          ["a", :created, [[], "92b0a48"]],
          ["b", :created, [[], "f0febf9"]],
          ["c", :created, [[], "a1a8457"]]
        ], commit.changes_introduced_by.sort
      end

      test 'shows additions, deletions or changes with a single parent' do
        repository = FileSystemGitRepository.new(project_path: File.join(@git_repositories_folder, 'valid_with_merge'))
        commit     = Commit.find_or_initialize_by_sha1(repository, 'ddd0c88d5360f5aca066075e45e33caa063f916b')

        assert_equal [
          ["a", :deleted, ["92b0a48", []]],
          ["b", :updated, [["f0febf9"], "9ee336d"]],
          ["d", :created, [[], "3870675"]]
        ], commit.changes_introduced_by.sort
      end

      test 'shows empty changes for usual merge commit' do
        repository = FileSystemGitRepository.new(project_path: File.join(@git_repositories_folder, 'valid_with_merge'))
        commit     = Commit.find_or_initialize_by_sha1(repository, 'e61ce5cf4178fd9e18f96862e52f192eeaf55b92')

        assert_equal [], commit.changes_introduced_by
      end

      test 'shows additions, deletions or updates for "evil" merge commit' do
        repository = FileSystemGitRepository.new(project_path: File.join(@git_repositories_folder, 'valid_with_merge'))
        commit     = Commit.find_or_initialize_by_sha1(repository, '56acfdb0b48b42e97c0714c4bd1263b47225acdf')

        assert_equal [
          ["c", :deleted, ["a1a8457", []]],
          ["d", :updated, [["3284dfe", "e2556d1"], "658ef45"]],
          ["f", :created, [[], "f1f803a"]]
        ], commit.changes_introduced_by.sort
      end

      test 'shows renames' do
        repository = FileSystemGitRepository.new(project_path: File.join(@git_repositories_folder, 'valid_with_merge'))
        commit     = Commit.find_or_initialize_by_sha1(repository, 'd07013e585bfc4844ae9e5b890bb4385516c3815')

        assert_equal [
          ["e -> A/e", :renamed, ["a04c515", "a04c515"]]
        ], commit.changes_introduced_by
      end
    end
  end
end
