class Blob < GitObject
  def validate_data
    true
  end

  def checkout!(destination_path = default_checkout_folder)
    raise "Blob cannot be checked out (blob data not loaded)." if !load_blob_data?

    # Oops, another violation of the Open-Closed Principle (Blobs should have no knowledge about ExecutableFiles or GroupWritableFiles).
    filemode = { ExecutableFile => 0755, GroupWritableFile => 0664, Blob => 0644 }[self.class]

    File.write destination_path, data
    File.chmod filemode, destination_path

    nil
  end

  def clone_into(target_repository)
    puts ">>> Cloning blob #{sha1}"

    target_repository.create_blob! data, sha1
  end

  remember :clone_into
end