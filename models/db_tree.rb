class DbTree < DbObject
  has_many :entries, class_name: 'DbTreeEntry', foreign_key: :tree_id

  def to_raw
    [:tree, entries.map { |entry| [entry.mode, entry.name, entry.git_object.sha1] }]

    # data = entries.map { |entry|
    #   entry.mode + " " + entry.name + "\0" + Sha1Util.byte_array_sha1(entry.git_object.sha1)
    # }.join
    #
    # "tree #{data.size}\0#{data}"
  end
end
