class GitRepository
  attr_reader :instances

  delegate :max_parents_count,      to: :head_commit
  delegate :checkout!, :clone_into, to: :head_commit_with_blob_data

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
    Commit.find_by_sha1(self, head_commit_sha1, options) if head_commit_sha1
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

  def create_commit!(branch_name, tree_sha1, parents_sha1s, author, committer, subject, source_sha1 = nil)
    commit_sha1 = create_commit_object!(tree_sha1, parents_sha1s, author, committer, subject, source_sha1)

    update_branch! branch_name, commit_sha1

    commit_sha1
  end

  def create_tree!(entries, source_sha1 = nil)
    create_tree_object! entries, source_sha1
  end

  def create_blob!(data, source_sha1 = nil)
    create_blob_object! data, source_sha1
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

  def find_cloned_git_object(source_sha1)
  end

  def validate
    head_commit_with_blob_data.validate_ancestors
  end

  def commit_count
    head_commit.ancestors_count
  end

  def ==(another_repository)
    head_commit_with_blob_data.ancestors_equal? another_repository.head_commit_with_blob_data
  end

  protected

  def create_commit_object!(tree_sha1, parents_sha1s, author, committer, subject, source_sha1 = nil)
    raise NotImplementedError
  end

  def create_tree_object!(entries, source_sha1 = nil)
    raise NotImplementedError
  end

  def create_blob_object!(data, source_sha1 = nil)
    raise NotImplementedError
  end
end