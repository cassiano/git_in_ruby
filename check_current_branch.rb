# To make sure all objects are "loose":
#
# 1) Move all pack files to a temp folder
# 2) For each pack file (.pack extensions), run: git unpack-objects < <pack>

require 'digest/sha1'
require 'zlib'

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
end

class GitObject
  SHA1_SIZE_IN_BYTES = 20

  # http://stackoverflow.com/questions/737673/how-to-read-the-mode-field-of-git-ls-trees-output
  MODES = {
    '100644' => 'Blob',
    '40000'  => 'Tree',
    '100755' => 'ExecutableFile',
    '120000' => 'SymLink',
    '160000' => 'GitSubModule',
    '100664' => 'GroupWriteableFile'
  }

  @@processed_cache = {}

  def initialize(sha1, level = 1)
    @sha1 = case sha1.size
      when 20 then GitObject.hex_string_sha1(sha1)
      when 40 then sha1
      else raise "Invalid SHA1 size (#{sha1.size})"
    end

    @level  = level
    @loaded = false
  end

  def load
    path = File.join('.git/objects/', @sha1[0, 2], @sha1[2, SHA1_SIZE_IN_BYTES * 2 - 2])

    raise ">>> File #{path} not found" unless File.exists?(path)

    zlib_content = File.read(path)
    raw_content  = Zlib::Inflate.inflate(zlib_content)
    header       = raw_content.split("\0")[0]
    data         = raw_content[(header.size + 1)..-1]
    type, size   = header.split
    size         = size.to_i

    @type        = type
    @size        = size
    @data        = data
    @raw_content = raw_content
    @loaded      = true
  end

  def self.hex_string_sha1(byte_sha1)
    byte_sha1.split('').map { |c| "%02x" % c.ord }.join
  end

  def validate
    puts "[#{@level}] Validating #{self.class.name} with SHA1 #{@sha1}"

    if !@@processed_cache[@sha1].nil?
      puts "Skipped!"
      return
    end

    check_content

    @@processed_cache[@sha1] = true
  end

  protected

  def check_content
    load unless @loaded

    expected_types = (self.class.ancestors - [Object, Kernel, BasicObject]).map { |klass| klass.name.underscore }
    expected_sha1  = Digest::SHA1.hexdigest(@raw_content)

    raise ">>> Invalid type '#{@type}' (expected '#{expected_types.join(', ')}')" unless expected_types.include?(@type)
    raise ">>> Invalid size #{@size} (expected #{@data.size})"                    unless @size == @data.size
    raise ">>> Invalid SHA1 '#{@sha1}' (expected '#{expected_sha1}')"             unless @sha1 == expected_sha1
  end
end

class Commit < GitObject
  def check_content
    super

    lines = @data.split("\n")

    tree    = Tree.new(lines.find { |line| line.split[0] == 'tree' }.split[1], @level)
    parents = lines.find_all { |line| line.split[0] == 'parent' }.map { |line| Commit.new(line.split[1], @level + 1) }

    tree.validate
    parents.each &:validate
  end
end

class Tree < GitObject
  def check_content
    super

    items = @data.scan(/(\d+) (.+?)\0(.{20})/m).map do |mode, name, sha1|
      raise "Unexpected mode #{mode} in file #{name}" unless MODES[mode]

      # Instantiate the object, based on its mode (Blob, Tree, ExecutableFile etc).
      Object.const_get(MODES[mode]).new sha1, @level
    end

    items.each &:validate
  end
end

class Blob < GitObject
end

class ExecutableFile < Blob
end

class NonCheckableFiles < GitObject
  def check_content
  end
end

class SymLink < NonCheckableFiles
end

class GitSubModule < NonCheckableFiles
end

class GroupWriteableFile < NonCheckableFiles
end

def run!
  head_ref_path   = File.read(File.join('.git/HEAD')).chomp[/\Aref: (.*)/, 1]
  branch_tip_sha1 = File.read(File.join('.git', head_ref_path)).chomp

  Commit.new(branch_tip_sha1).validate
end

run! if __FILE__ == $0
