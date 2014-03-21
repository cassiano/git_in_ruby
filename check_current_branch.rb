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
  VALID_MODES = {
    '100644' => 'Blob',
    '40000'  => 'Tree',
    '100755' => 'ExecutableFile',
    '120000' => 'SymLink',
    '160000' => 'GitSubModule',
    '100664' => 'GroupWriteableFile'
  }

  @@instances = {}

  def self.find_or_initialize_by(sha1, commit_level = 1)
    sha1 = case sha1.size
      when 20 then hex_string_sha1(sha1)
      when 40 then sha1
      else raise "\n>>> Invalid SHA1 size (#{sha1.size})"
    end

    @@instances[sha1] ||= new(sha1, commit_level)
  end

  def initialize(sha1, commit_level)
    @sha1         = sha1
    @commit_level = commit_level
    @validated    = false

    load_from_file_system
  end

  def self.hex_string_sha1(byte_sha1)
    byte_sha1.bytes.map { |b| "%02x" % b }.join
  end

  def validate
    print "\n(#{@commit_level}) Validating #{self.class.name} with SHA1 #{@sha1} "

    if @validated
      print "[skipped]"
      return
    end

    check_content

    @validated = true
  end

  protected

  def load_from_file_system
    path = File.join('.git/objects/', @sha1[0, 2], @sha1[2, SHA1_SIZE_IN_BYTES * 2 - 2])

    raise "\n>>> File '#{path}' not found! Have you unpacked all pack files?" unless File.exists?(path)

    zlib_content          = File.read(path)
    raw_content           = Zlib::Inflate.inflate(zlib_content)
    first_null_byte_index = raw_content.index("\0")
    header                = raw_content[0...first_null_byte_index]
    data                  = raw_content[(first_null_byte_index + 1)..-1]
    type, size            = header.split

    @type             = type
    @size             = size.to_i
    @raw_content_sha1 = Digest::SHA1.hexdigest(raw_content)
    @data             = data if [:commit, :tree].include?(type.to_sym)
    @data_size        = data.size
  end

  def check_content
    expected_types = (self.class.ancestors - GitObject.ancestors).map { |klass| klass.name.underscore }

    raise "\n>>> Invalid type '#{@type}' (expected one of [#{expected_types.join(', ')}])"  unless expected_types.include?(@type)
    raise "\n>>> Invalid size #{@size} (expected #{@data_size})"                            unless @size == @data_size
    raise "\n>>> Invalid SHA1 '#{@sha1}' (expected '#{@raw_content_sha1}')"                 unless @sha1 == @raw_content_sha1
  end
end

class Commit < GitObject
  def check_content
    super

    lines = @data.split("\n")

    if (tree_line = lines.find { |line| line.split[0] == 'tree' })
      tree_sha1 = tree_line.split[1]
    else
      raise "\n>>> Missing required tree in commit."
    end

    @tree = Tree.find_or_initialize_by(tree_sha1, @commit_level)

    @parents = lines.find_all { |line| line.split[0] == 'parent' }.map do |line|
      commit_sha1 = line.split[1]

      Commit.find_or_initialize_by commit_sha1, @commit_level + 1
    end

    @tree.validate
    @parents.each &:validate
  end
end

class Tree < GitObject
  def check_content
    super

    @entries = @data.scan(/(\d+) (.+?)\0([\x00-\xFF]{20})/).map do |mode, name, sha1|
      raise "\n>>> Invalid mode #{mode} in file '#{name}'" unless VALID_MODES[mode]

      print "\n  #{name}"

      # Instantiate the object, based on its mode (Blob, Tree, ExecutableFile etc).
      Object.const_get(VALID_MODES[mode]).find_or_initialize_by sha1, @commit_level
    end

    @entries.each &:validate
  end
end

class Blob < GitObject
end

class ExecutableFile < Blob
end

class SkippedFile < Blob
  def initialize(sha1, commit_level)
    @sha1         = sha1
    @commit_level = commit_level

    # Indicate the file has already been validated, so it can be safely skipped.
    @validated = true
  end
end

class SymLink < SkippedFile
end

class GitSubModule < SkippedFile
end

class GroupWriteableFile < SkippedFile
end

def run!
  head_ref_path   = File.read(File.join('.git/HEAD')).chomp[/\Aref: (.*)/, 1]
  branch_tip_sha1 = File.read(File.join('.git', head_ref_path)).chomp

  Commit.find_or_initialize_by(branch_tip_sha1).validate
end

run! if __FILE__ == $0
