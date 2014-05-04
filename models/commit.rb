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

  # PS: shows poor performance and uses excessive heap space for large repositories (e.g. for the Git source ode, with 36170+ commits, it took
  # 278 seconds in my Macbook).
  def commit_count
    1 + ancestor_sha1s.size
  end

  def ancestor_sha1s
    parents.inject([]) { |acc, parent| acc + [parent.sha1[0..8]] + parent.ancestor_sha1s }.uniq
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

  remember :tree, :parents, :clone_into, :max_parents_count, :commit_count, :ancestor_sha1s
end