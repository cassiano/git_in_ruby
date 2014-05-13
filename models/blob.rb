class Blob < GitObject
  self.filemode = 0644

  def validate_data
    true
  end

  def checkout!(destination_path = default_checkout_folder)
    raise "Blob cannot be checked out (blob data not loaded)." if !load_blob_data?

    File.write destination_path, data
    File.chmod self.class.filemode, destination_path

    nil
  end

  def clone_into(target_repository)
    puts "(#{commit_level}) Cloning blob #{sha1}"

    raise "Blob cannot be cloned (blob data not loaded)." if !load_blob_data?

    if (clone_sha1 = target_repository.find_cloned_git_object(sha1))
      return clone_sha1
    end

    target_repository.create_blob! data, sha1
  end

  def ==(another_blob)
    raise "Blobs cannot be compared (blob data not loaded)." if !load_blob_data? || !another_blob.load_blob_data?

    data == another_blob.data
  end

  remember :clone_into, :==
end