module Sha1Util
  def standardized_sha1(sha1)
    case sha1.size
      when 20 then hex_string_sha1(sha1)
      when 40 then sha1
      else raise ">>> Invalid SHA1 size (#{sha1.size})"
    end
  end

  def hex_string_sha1(byte_sha1)
    byte_sha1.bytes.map { |b| "%02x" % b }.join
  end
end
