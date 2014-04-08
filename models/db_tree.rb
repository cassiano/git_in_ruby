class DbTree < DbObject
  has_many :entries, class_name: 'DbTreeEntry', foreign_key: :tree_id

  def to_raw
    [:tree, entries.map { |entry| [entry.mode, entry.name, entry.git_object.sha1] }]
  end
end
