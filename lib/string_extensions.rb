class String
  def underscore
    word = self.dup
    word.gsub!(/::/, '/')
    word.gsub!(/([A-Z]+)([A-Z][a-z])/,'\1_\2')
    word.gsub!(/([a-z\d])([A-Z])/,'\1_\2')
    word.tr!("-", "_")
    word.downcase!
    word
  end

  def camel_case
    return self if self !~ /_/ && self =~ /[A-Z]+.*/
    split('_').map(&:capitalize).join
  end

  def find_valid_encoding
    encodings = %w(UTF-8 ISO-8859-1)

    encodings.find do |encoding|
      self.dup.force_encoding(encoding).valid_encoding?
    end
  end

  def find_and_apply_valid_encoding
    self.force_encoding find_valid_encoding
  end
end
