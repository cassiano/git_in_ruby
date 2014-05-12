class GitSubModule < SkippedFile
  add_mode self, '160000'

  def load
  end

  def validate
    true
  end
end
