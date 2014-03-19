# To make sure all objects are "loose":
#
# 1) Move all pack files to a temp folder
# 2) For each pack file (.pack extensions), run: git unpack-objects < <pack>

require 'digest/sha1'
require 'zlib'

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

  @@cache = {}

  def initialize(sha1)
    @sha1 = case sha1.size
      when 20 then GitObject.sha1_as_40_character_string(sha1)
      when 40 then sha1
      else raise "Invalid SHA1 size (#{sha1.size})"
    end
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
  end

  def self.sha1_as_40_character_string(sha1)
    sha1.split('').map { |c| "%02x" % c.ord }.join
  end

  def check
    puts "Checking #{self.class.name} with SHA1 #{@sha1}..."

    puts("Skipped!") and return unless @@cache[@sha1]

    load
    check_common_data @type

    @@cache[@sha1] = true
  end

  protected

  def check_common_data(type)
    raise ">>> Invalid type '#{@type}' (expected '#{type}')" unless @type == type
    raise ">>> Invalid size #{@size} (expected #{@data.size})" unless @size == @data.size
    raise ">>> Invalid SHA1 '#{Digest::SHA1.hexdigest(@raw_content)}' (expected '#{@sha1}')" unless Digest::SHA1.hexdigest(@raw_content) == @sha1
  end
end

class Commit < GitObject
  def check
    super

    lines = @data.split("\n")

    tree    = Tree.new(lines.find { |line| line.split[0] == 'tree' }.split[1])
    parents = lines.find_all { |line| line.split[0] == 'parent' }.map { |line| Commit.new line.split[1] }

    tree.check
    parents.each &:check
  end
end

class Tree < GitObject
  def check
    super

    items = @data.scan(/(\d+) .+?\0(.{20})/m).map do |mode, sha1|
      raise "Unexpected mode #{mode}" unless MODES[mode]

      Object.const_get(MODES[mode]).new sha1
    end

    items.each &:check
  end
end

class Blob < GitObject
end

class ExecutableFile < GitObject
end

class SymLink < GitObject
  def check
  end
end

class GitSubModule < GitObject
  def check
  end
end

class GroupWriteableFile < GitObject
  def check
  end
end

def run!
  head_ref_path   = File.read(File.join('.git/HEAD')).chomp[/\Aref: (.*)/, 1]
  branch_tip_sha1 = File.read(File.join('.git', head_ref_path)).chomp

  Commit.new(branch_tip_sha1).check
end

run! if __FILE__ == $0
