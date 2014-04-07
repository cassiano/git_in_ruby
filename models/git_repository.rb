class GitRepository
  extend Memoize

  attr_reader :instances

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

  def head_fsck
    head_commit(load_blob_data: true).validate
  end

  def head_commit_sha1
    raise NotImplementedError
  end

  def load_object(sha1)
    raise NotImplementedError
  end

  # Must return a hash with the following keys: type, size and data.
  def parse_object(raw_content)
    raise NotImplementedError
  end

  def create_commit!(branch_name, tree_sha1, parents_sha1, author, committer, subject)
    data        = format_commit_data(tree_sha1, parents_sha1, author, committer, subject)
    commit_sha1 = create_git_object!(:commit, data)

    update_branch! branch_name, commit_sha1

    commit_sha1
  end

  def create_tree!(entries)
    data = format_tree_data(entries)

    create_git_object! :tree, data
  end

  def create_blob!(data)
    create_git_object! :blob, data
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

  protected

  def create_git_object!(type, data)
    raise NotImplementedError
  end

  def format_commit_data(tree_sha1, parents_sha1, author, committer, subject)
    raise NotImplementedError
  end

  def format_tree_data(entries)
    raise NotImplementedError
  end

  remember :head_commit_sha1
end