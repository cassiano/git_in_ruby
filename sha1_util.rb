module Sha1Util
  def self.standardized_sha1(sha1)
    case sha1.size
      when 20 then hex_string_sha1(sha1)
      when 40 then sha1
      else raise ">>> Invalid SHA1 size (#{sha1.size})"
    end
  end

  def self.hex_string_sha1(byte_sha1)
    byte_sha1.bytes.map { |b| "%02x" % b }.join
  end

  def self.byte_array_sha1(sha1)
    (1..20).map { |i| sha1[(i - 1) * 2, 2].to_i(16).chr }.join
  end
end
