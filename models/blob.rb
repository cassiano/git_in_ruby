class Blob < GitObject
  def validate_data
  end

  def checkout!(destination_path = File.join('checkout_files', sha1[0..6]))
    filemode = { ExecutableFile => 0755, GroupWritableFile => 0664, Blob => 0644 }[self.class]

    File.write destination_path, data
    File.chmod filemode, destination_path
  end

  def clone_into(target_repository)
    puts ">>> Cloning blob #{sha1}"

    target_repository.create_blob! data, self.sha1
  end
end