class SkippedFile < Blob
  def checkout!(destination_path = default_checkout_folder)
    puts "Skipping #{sha1}..."
  end

  def clone_into(target_repository)
    puts "Skipping #{sha1}..."
    nil
  end
end
