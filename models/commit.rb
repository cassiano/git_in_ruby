class Commit < GitObject
  attr_reader :tree_sha1, :parents_sha1s, :subject, :author, :committer

  def tree
    Tree.find_or_initialize_by_sha1 repository, tree_sha1, commit_level: commit_level, load_blob_data: load_blob_data?
  end

  def parents
    parents_sha1s.map do |sha1|
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
    updates_and_creations.find_all { |(_, action, _)| action == :deleted }.inject(updates_and_creations) do |changes, deleted_file|
      if (created_file = changes.find { |(_, action, (_, created_sha1))| action == :created && created_sha1 == deleted_file[2][0] })
        changes.delete created_file
        changes.delete deleted_file
        changes << ["#{deleted_file[0]} -> #{created_file[0]}", :renamed, [deleted_file[2][0], created_file[2][1]]]
      end

      changes
    end
  end

  # def validate_data
  #   tree.validate
  #   parents.each &:validate
  #
  #   true
  # end

  # def clone_into(target_repository, branch = 'master')
  #   puts "(#{commit_level}) Cloning commit #{sha1}"
  #
  #   if (clone_sha1 = target_repository.find_cloned_git_object(sha1))
  #     return clone_sha1
  #   end
  #
  #   parents_clones_sha1s = parents.map { |parent| parent.clone_into(target_repository, branch) }
  #   tree_clone_sha1      = tree.clone_into(target_repository)
  #
  #   target_repository.create_commit! branch, tree_clone_sha1, parents_clones_sha1s, author, committer, subject, sha1
  # end

  # def max_parents_count
  #   ([{ sha1: sha1, count: parents.count }] + parents.map(&:max_parents_count)).max { |a, b| a[:count] <=> b[:count] }
  # end

  #########################
  # Non-recursive versions.
  #########################

  def validate_ancestors
    visit_ancestors do |commit, index|
      # puts index if index % 100 == 0

      commit.validate
    end

    true
  end

  def validate_data
    tree.validate
  end

  def ancestors_count
    visit_ancestors.count
  end

  def max_parents_count
    { sha1: nil, count: -1 }.tap do |max|
      visit_ancestors do |commit, index|
        # puts "[#{index}] Max so far: #{max[:count]} (#{max[:sha1]})" if index % 1000 == 0

        if (count = commit.parents.count) > max[:count]
          max[:sha1]  = commit.sha1
          max[:count] = count
        end
      end
    end
  end

  def clone_into(target_repository, branch = 'master')
    puts 'Phase I: cloning trees for commits not yet cloned...'

    cloned_commits_and_trees = visit_ancestors do |commit, index|
      puts "(#{commit.commit_level}) Cloning commit #{commit.sha1} [##{index + 1}]"

      if (clone_sha1 = target_repository.find_cloned_git_object(commit.sha1))
        { type: :commit, sha1: clone_sha1 }
      else
        { type: :tree, sha1: commit.tree.clone_into(target_repository) }
      end
    end

    puts "\nPhase II: cloning pending commits, based on the trees just cloned..."

    cloned_trees = cloned_commits_and_trees.find_all { |_, data| data[:type] == :tree }.reverse

    while !cloned_trees.empty? do
      puts "#{cloned_trees.count} trees still pending"

      # Find the 1st commit which have all parents already cloned (remember that having no parents also satisfy this criteria).
      # Notice that, for performance reasons, the cloned trees are searched in reversed order (so older commits are looked 1st).
      commit_tree_match = cloned_trees.find do |commit_sha1, data|
        commit = Commit.find_or_initialize_by_sha1(repository, commit_sha1)

        commit.parents.all? { |parent| cloned_commits_and_trees[parent.sha1][:type] == :commit }
      end

      assert { !commit_tree_match.nil? }

      next_commit_to_clone = Commit.find_or_initialize_by_sha1(repository, commit_tree_match[0])

      parents_clones = next_commit_to_clone.parents.map do |parent|
        assert { cloned_commits_and_trees[parent.sha1][:type] == :commit }

        cloned_commits_and_trees[parent.sha1][:sha1]
      end

      cloned_commit_sha1 = target_repository.create_commit!(
        branch,
        commit_tree_match[1][:sha1],
        parents_clones,
        next_commit_to_clone.author,
        next_commit_to_clone.committer,
        next_commit_to_clone.subject,
        next_commit_to_clone.sha1
      )

      assert { !cloned_commit_sha1.nil? }

      # Replace the cloned tree by a cloned commit reference.
      cloned_commits_and_trees[next_commit_to_clone.sha1] = { type: :commit, sha1: cloned_commit_sha1 }

      # Delete the just cloned commit's tree from the cloned_trees collection.
      cloned_trees.delete commit_tree_match
    end

    assert { cloned_commits_and_trees[sha1][:type] == :commit }

    cloned_commits_and_trees[sha1][:sha1]
  end

  def ancestors_equal?(another_commit)
    another_commit_ancestors = another_commit.visit_ancestors { |commit| commit }.to_a

    visit_ancestors do |commit, i|
      puts i if i % 10 == 0

      return false unless commit == another_commit_ancestors[i].last
    end

    true
  end

  def ==(another_commit)
    [:author, :committer, :subject, :tree].all? do |attribute|
      equals? self.send(attribute), another_commit.send(attribute), attribute
    end
  end

  protected

  def parse_data(data)
    parsed_data = repository.parse_commit_data(data)

    @tree_sha1     = parsed_data[:tree_sha1]
    @parents_sha1s = parsed_data[:parents_sha1s]
    @author        = parsed_data[:author]
    @committer     = parsed_data[:committer]
    @subject       = parsed_data[:subject]
  end

  # Visits all commit ancestors, starting by itself, yielding the supplied block (if any) the current commit and a sequential index.
  def visit_ancestors
    index       = 0
    visit_queue = {}    # We will use hashes instead of arrays (for speed). See: https://gist.github.com/cassiano/c61bf6d553cc0bea15fe
    visited     = {}

    # Start scheduling a visit for the node pointed to by 'self'.
    visit_queue[self] = nil     # Notice the hash value itself is not important, but only the key.

    # Repeat while there are still nodes to be visited.
    while !visit_queue.empty? do
      current = visit_queue.shift.first     # Retrieve the oldest key.

      # If any block supplied, visit the node.
      result = yield(current, index) if block_given?

      visited[current.sha1] = result

      # Schedule a visit for each of the current node's parent.
      current.parents.each do |parent|
        # But do it only if node has not yet been visited nor already marked for visit (in the visit queue).
        visit_queue[parent] = nil unless visit_queue.has_key?(parent) || visited.has_key?(parent.sha1)
      end

      index += 1
    end

    visited
  end

  remember :tree, :parents, :clone_into, :max_parents_count, :ancestors_count, :validate, :==, :ancestors_equal?
end
