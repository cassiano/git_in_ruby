class AssertionError < RuntimeError
end

def assert
  raise AssertionError unless yield
end

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
    if parents.count == 0
      nil
    elsif parents.count == 1
      parents[0]
    else
      raise "More than one parent commit found."
    end
  end

  # def validate_data
  #   tree.validate
  #   parents.each &:validate
  #
  #   true
  # end

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

  # def max_parents_count
  #   ([{ sha1: sha1, count: parents.count }] + parents.map(&:max_parents_count)).max { |a, b| a[:count] <=> b[:count] }
  # end

  #########################
  # Non-recursive versions.
  #########################

  def validate_ancestors
    visit_ancestors do |commit, index|
      puts index if index % 100 == 0

      commit.validate
    end

    true
  end

  def validate_data
    tree.validate
  end

  def commit_count
    visit_ancestors.count
  end

  def max_parents_count
    { sha1: nil, count: -1 }.tap do |max|
      visit_ancestors do |commit, index|
        puts "[#{index}] Max so far: #{max[:count]} (#{max[:sha1]})" if index % 1000 == 0

        if (count = commit.parents.count) > max[:count]
          max[:sha1]  = commit.sha1
          max[:count] = count
        end
      end
    end
  end

  def clone_into(target_repository, branch = 'master')
    cloned_commits_and_trees = visit_ancestors do |commit|
      puts "(#{commit.commit_level}) Cloning commit #{commit.sha1}"

      if (clone_sha1 = target_repository.find_cloned_git_object(commit.sha1))
        { type: :commit, sha1: clone_sha1 }
      else
        { type: :tree, sha1: commit.tree.clone_into(target_repository) }
      end
    end

    while !(cloned_trees = cloned_commits_and_trees.find_all { |_, data| data[:type] == :tree }).empty? do
      next_commit_to_clone = nil

      cloned_trees.reverse.each do |commit_sha1, data|
        # Find a commit (any) whose parents have already been cloned.
        next_commit_to_clone = Commit.find_or_initialize_by_sha1(repository, commit_sha1)

        parents_cloned = next_commit_to_clone.parents.all? do |parent|
          cloned_commits_and_trees[parent.sha1][:type] == :commit
        end

        break if parents_cloned
      end

      break if !next_commit_to_clone

      cloned_commit_sha1 = target_repository.create_commit!(
        branch,
        cloned_commits_and_trees[next_commit_to_clone.sha1][:sha1],
        next_commit_to_clone.parents.map do |parent|
          assert { cloned_commits_and_trees[parent.sha1][:type] == :commit }

          cloned_commits_and_trees[parent.sha1][:sha1]
        end,
        next_commit_to_clone.author,
        next_commit_to_clone.committer,
        next_commit_to_clone.subject,
        next_commit_to_clone.sha1
      )

      cloned_commits_and_trees[next_commit_to_clone.sha1] = { type: :commit, sha1: cloned_commit_sha1 }
    end

    assert { cloned_commits_and_trees[sha1][:type] == :commit }

    cloned_commits_and_trees[sha1][:sha1]
  end

  protected

  def parse_data(data)
    parsed_data = repository.parse_commit_data(data)

    @tree_sha1    = parsed_data[:tree_sha1]
    @parents_sha1 = parsed_data[:parents_sha1]
    @author       = parsed_data[:author]
    @committer    = parsed_data[:committer]
    @subject      = parsed_data[:subject]
  end

  # Visits all commit ancestors, starting by itself.
  def visit_ancestors(&block)
    index       = 0
    visit_queue = []
    visited     = {}    # Why haven't I used an ordinary array for this as well? Because hashes have proved to be more than 3000
                        # times faster for searches (in average) for 37000 elements (# of commits of the Git source repository).
                        # See: https://gist.github.com/cassiano/c61bf6d553cc0bea15fe

    # Start scheduling a visit for the node pointed to by 'self'.
    visit_queue.push self

    # Repeat while there are still nodes to be visited.
    while !visit_queue.empty? do
      current = visit_queue.shift

      # If any block supplied, visit the node.
      result = yield(current, index) if block_given?

      visited[current.sha1] = result

      # Schedule a visit for each of the current node's parent.
      current.parents.each do |parent|
        # But do it only if node has not yet been visited nor already marked for visit (in the visit queue).
        visit_queue.push(parent) unless visited.has_key?(parent.sha1) || visit_queue.include?(parent)
      end

      index += 1
    end

    visited
  end

  remember :tree, :parents, :clone_into, :max_parents_count, :commit_count, :validate
end
