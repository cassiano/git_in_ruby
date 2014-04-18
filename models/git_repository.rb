require 'forwardable'

class GitRepository
  extend Memoize
  extend Forwardable

  attr_reader :instances

  def_delegator :head_commit,                 :commit_count
  def_delegator :head_commit,                 :max_parents_count
  def_delegator :head_commit_with_blob_data,  :checkout!
  def_delegator :head_commit_with_blob_data,  :validate

  def initialize(options = {})
    options = {
      bare_repository: false
    }.merge(options)

    @instances       = {}
    @bare_repository = !!options[:bare_repository]
  end

  def bare_repository?
    @bare_repository
  end

  def head_commit(options = {})
    Commit.find_or_initialize_by_sha1 self, head_commit_sha1, options
  end

  def head_commit_with_blob_data(options = {})
    head_commit options.merge(load_blob_data: true)
  end

  def head_commit_sha1
    raise NotImplementedError
  end

  # TODO: verify whether this method should be concrete and use the "template method" design pattern, calling methods :parse_object
  # and :sha1_from_raw_content!
  # Must return a hash with the following keys: type, size, data and content_sha1.
  def load_object(sha1)
    raise NotImplementedError
  end

  # TODO: verify whether this method should really be abstract! Shouldn't it belong only to subclasses which decide to implement it?
  # Must return a hash with the following keys: type, size and data.
  def parse_object(raw_content)
    raise NotImplementedError
  end

  # TODO: verify whether this method should really be abstract! Shouldn't it belong only to subclasses which decide to implement it?
  def sha1_from_raw_content(raw_content)
    raise NotImplementedError
  end

  def create_commit!(branch_name, tree_sha1, parents_sha1, author, committer, subject, clone_sha1 = nil)
    data        = format_commit_data(tree_sha1, parents_sha1, author, committer, subject)
    commit_sha1 = create_commit_object!(data, clone_sha1)

    update_branch! branch_name, commit_sha1

    commit_sha1
  end

  def create_tree!(entries, clone_sha1 = nil)
    data = format_tree_data(entries)

    create_tree_object! data, clone_sha1
  end

  def create_blob!(data, clone_sha1 = nil)
    create_blob_object! data, clone_sha1
  end

  def parse_commit_data(commit)
    raise NotImplementedError
  end

  def parse_tree_data(tree)
    raise NotImplementedError
  end

  def update_branch!(name, commit_sha1)
    raise NotImplementedError
  end

  def branches
    raise NotImplementedError
  end

  def clone_into(target_repository, branch = 'master')
    head_commit(load_blob_data: true).clone_into target_repository, branch
  end

  protected

  def create_commit_object!(data, clone_sha1 = nil)
    raise NotImplementedError
  end

  def create_tree_object!(data, clone_sha1 = nil)
    raise NotImplementedError
  end

  def create_blob_object!(data, clone_sha1 = nil)
    raise NotImplementedError
  end

  # Generates (commit) data for the :create_git_object! method.
  def format_commit_data(tree_sha1, parents_sha1, author, committer, subject)
    raise NotImplementedError
  end

  # Generates (tree) data for the :create_git_object! method.
  def format_tree_data(entries)
    raise NotImplementedError
  end
end