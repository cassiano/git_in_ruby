class Blob < GitObject
  def validate_data
  end

  def clone_into(target_repository)
    puts ">>> Cloning blob #{sha1}"

    target_repository.create_blob! data, self.sha1
  end
end