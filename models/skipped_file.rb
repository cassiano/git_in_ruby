class SkippedFile < Blob
  def checkout!(destination_path = default_checkout_folder)
    puts "Skipping #{filename_or_path}..."
  end
end
