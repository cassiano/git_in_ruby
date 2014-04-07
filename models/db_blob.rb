class DbBlob < DbObject
  alias_attribute :data, :blob_data

  def to_raw
    [:blob, data]

    # "blob #{data.size}\0#{data}"
  end
end
