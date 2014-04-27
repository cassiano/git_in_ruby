class DbTree < DbObject
  has_many :entries, -> { order :id }, class_name: 'DbTreeEntry', foreign_key: :tree_id

  def to_raw
    [
      :tree,
      entries.map do |entry|
        [entry.mode, entry.name, entry.git_object.sha1]
      end
    ]
  end
end
