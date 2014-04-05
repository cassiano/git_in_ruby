class DbBlob < DbObject
  alias_attribute :data, :blob_data

  def to_raw
    [:blob, data]
  end
end
