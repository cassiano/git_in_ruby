class Commit < GitObject
  attr_reader :tree_sha1, :parents_sha1, :subject, :author, :committer

  def tree
    Tree.find_or_initialize_by_sha1 repository, tree_sha1, commit_level: commit_level, load_blob_data: load_blob_data?
  end

  def parents
    parents_sha1.map do |sha1|
      Commit.find_or_initialize_by_sha1 repository, sha1, commit_level: commit_level + 1, load_blob_data: load_blob_data?
    end
  end

  def parent
    if parents.size == 0
      nil
    elsif parents.size == 1
      parents[0]
    else
      raise "More than one parent commit found."
    end
  end

  def validate_data
    tree.validate
    parents.each &:validate

    true
  end

  def checkout!(destination_path = default_checkout_folder)
    FileUtils.mkpath destination_path
    tree.checkout! destination_path

    nil
  end

  def changes_introduced_by
    updates_and_creations = tree.changes_between(parents.map(&:tree))

    # Find deletions between the current commit and its parents by finding the *common* additions the other way around, i.e.
    # between each of the parents and the current commit, then transforming them into deletions.
    deletions = parents.map { |parent|
      parent.tree.changes_between([tree]).find_all { |(_, action, _)| action == :created }.map { |name, _, sha1s| [name, :deleted, sha1s.reverse] }
    }.inject(:&) || []
    updates_and_creations.concat deletions

    # Identify renamed files, replacing the :created and :deleted associated pair by a single :renamed one.
    updates_and_creations.find_all { |(_, action, _)| action == :deleted }.inject(updates_and_creations) { |changes, deleted_file|
      if (created_file = changes.find { |(_, action, (_, created_sha1))| action == :created && created_sha1 == deleted_file[2][0] })
        changes.delete created_file
        changes.delete deleted_file
        changes << ["#{deleted_file[0]} -> #{created_file[0]}", :renamed, [deleted_file[2][0], created_file[2][1]]]
      end

      changes
    }
  end

  def clone_into(target_repository, branch = 'master')
    puts "(#{commit_level}) Cloning commit #{sha1}"

    if (clone_sha1 = target_repository.find_cloned_git_object(sha1))
      return clone_sha1
    end

    parents_clones_sha1s = parents.map { |parent| parent.clone_into(target_repository, branch) }
    tree_clone_sha1      = tree.clone_into(target_repository)

    target_repository.create_commit! branch, tree_clone_sha1, parents_clones_sha1s, author, committer, subject, sha1
  end

  def max_parents_count
    ([{ sha1: sha1, count: parents.count }] + parents.map(&:max_parents_count)).max { |a, b| a[:count] <=> b[:count] }
  end

  # Non-recursive (iterative) version, which generally shows very good performance (e.g. for the Git source code, with
  # 36170+ commits, it took only 12 seconds in my Macbook).
  def commit_count
    visit_queue = []
    visited     = {}    # Why haven't I used an ordinary array for this as well? Because hashes proved to be more
                        # than 3000 times faster for searches (in average) for 37000 elements.
                        # See: https://gist.github.com/cassiano/c61bf6d553cc0bea15fe

    # Start scheduling a visit for the node pointed to by 'self'.
    visit_queue.push self

    # Repeat while there are still nodes to be visited.
    while !visit_queue.empty? do
      current = visit_queue.shift

      # Mark the current node as "visited".
      visited[current] = true

      # Schedule a visit for each of the current node's parent.
      current.parents.each do |parent|
        # But do it only if node has not yet been visited nor already marked for visit (in the visit queue).
        visit_queue.push(parent) unless visited.has_key?(parent) || visit_queue.include?(parent)
      end
    end

    visited.count
  end

  def visit_tree(&block)
    visit_queue = []
    visited     = {}

    visit_queue.push self

    while !visit_queue.empty? do
      current = visit_queue.shift

      result = block.call(current)

      visited[current.sha1] = result

      current.parents.each do |parent|
        visit_queue.push(parent) unless visited.has_key?(parent.sha1) || visit_queue.include?(parent)
      end
    end

    visited
  end

  # r1 = FileSystemGitRepository.new project_path: 'test/git_repositories/valid_with_merge'
  # r2 = RdbmsGitRepository.new
  #
  # branch = 'master'
  # target_repository = r1
  #
  # result = r1.head_commit(load_blob_data: true).visit_tree do |c|
  #   puts "(#{c.commit_level}) Cloning commit #{c.sha1}"
  #
  #   if (clone_sha1 = target_repository.find_cloned_git_object(c.sha1))
  #     return clone_sha1
  #   end
  #
  #   parents_clones_sha1s = c.parents.map { |parent| parent.clone_into(target_repository, branch) }
  #   tree_clone_sha1      = c.tree.clone_into(target_repository)
  #
  #   target_repository.create_commit! branch, tree_clone_sha1, parents_clones_sha1s, c.author, c.committer, c.subject, c.sha1
  # end
  #
  # result = r1.head_commit(load_blob_data: true).visit_tree(&:validate)

  protected

  def parse_data(data)
    parsed_data = repository.parse_commit_data(data)

    @tree_sha1    = parsed_data[:tree_sha1]
    @parents_sha1 = parsed_data[:parents_sha1]
    @author       = parsed_data[:author]
    @committer    = parsed_data[:committer]
    @subject      = parsed_data[:subject]
  end

  remember :tree, :parents, :clone_into, :max_parents_count, :commit_count
end
