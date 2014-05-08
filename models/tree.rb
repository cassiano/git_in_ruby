class Tree < GitObject
  attr_reader :entries_info

  def entries
    entries_info.inject({}) do |items, (mode, name, sha1)|
      raise InvalidModeError, "Invalid mode #{mode} in file '#{name}'" unless VALID_MODES[mode]

      # Instantiate the object, based on its mode (Blob, Tree, ExecutableFile etc).
      items.merge name => Object.const_get(VALID_MODES[mode]).find_or_initialize_by_sha1(
        repository, sha1, commit_level: commit_level, load_blob_data: load_blob_data?
      )
    end
  end

  def validate_data
    entries.values.each &:validate

    true
  end

  def checkout!(destination_path = default_checkout_folder)
    puts "Creating folder #{destination_path}"

    FileUtils.mkpath destination_path

    entries.each do |name, entry|
      filename_or_path = destination_path ? File.join(destination_path, name) : name

      puts "Checking out #{filename_or_path}"

      entry.checkout! filename_or_path
    end

    nil
  end

  def changes_between(other_trees, base_path = nil)
    entries.inject([]) do |changes, (name, entry)|
      filename_or_path = base_path ? File.join(base_path, name) : name

      other_entries = other_trees.map { |tree| tree.entries[name] }.compact

      # For merge rules, check: http://thomasrast.ch/git/evil_merge.html
      if other_entries.empty?
        action = :created
        sha1s  = [[], entry.sha1[0..6]]
      elsif !other_entries.map(&:sha1).include?(entry.sha1)
        action = :updated
        sha1s  = [other_entries.map { |e| e.sha1[0..6] }.compact.uniq, entry.sha1[0..6]]
      end

      if action   # A nil action indicates an unchanged file.
        if Tree === entry
          changes.concat entry.changes_between(other_entries.find_all { |e| Tree === e }, filename_or_path)
        else    # Blob or one of its subclasses.
          changes << [filename_or_path, action, sha1s]
        end
      end

      changes
    end
  end

  def clone_into(target_repository)
    puts "(#{commit_level}) Cloning tree #{sha1}"

    if (clone_sha1 = target_repository.find_cloned_git_object(sha1))
      return clone_sha1
    end

    entries_clones = entries.map { |name, git_object|
      [git_object.class.name.underscore.to_sym, name, git_object.clone_into(target_repository)]
      }.reject { |entry| !entry[2] }

    target_repository.create_tree! entries_clones, sha1
  end

  protected

  def parse_data(data)
    parsed_data = repository.parse_tree_data(data)

    @entries_info = parsed_data[:entries_info]
  end

  remember :entries, :changes_between, :clone_into
end