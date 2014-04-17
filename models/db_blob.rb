require 'zlib'

class DbBlob < DbObject
  alias_attribute :data, :blob_data

  def to_raw
    [:blob, Zlib::Inflate.inflate(data)]
  end
end
