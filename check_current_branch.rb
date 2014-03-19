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
    '100755' => 'Blob',         # Executable file
    '120000' => 'GitObject',    # Symbolic link
    '160000' => 'GitObject',    # Git submodule
    '100664' => 'GitObject'     # Group writeable file
  }

  def initialize(sha1)
    @sha1 = sha1.size == 20 ? GitObject.sha1_as_40_character_string(sha1) : sha1
  end

  @@cache = {}

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
  end

  protected

  def check_common_data(type)
    raise ">>> Invalid type '#{commit[0]}' (expected '#{type}')" unless @type == type
    raise ">>> Invalid size #{@size} (expected #{@data.size})" unless @size == @data.size
    raise ">>> Invalid SHA1 '#{Digest::SHA1.hexdigest(@raw_content)}' (expected '#{@sha1}')" unless Digest::SHA1.hexdigest(@raw_content) == @sha1
  end
end

class Commit < GitObject
  @@cache[:commits] = {}

  def check
    puts "Checking commit #{@sha1}..."

    if @@cache[:commits][@sha1]
      puts "Skipped!"
      return
    end

    load

    commit_data  = @data.split("\n")
    tree_sha1    = commit_data.find { |line| line.split[0] == 'tree' }.split[1]
    parents_sha1 = commit_data.find_all { |line| line.split[0] == 'parent' }.map { |line| line.split[1] }

    check_common_data 'commit'

    Tree.new(tree_sha1).check

    parents_sha1.each { |sha1| Commit.new(sha1).check }

    @@cache[:commits][@sha1] = true
  end
end

class Tree < GitObject
  @@cache[:trees] = {}

  def check
    puts "Checking tree #{@sha1}..."

    if @@cache[:trees][@sha1]
      puts "Skipped!"
      return
    end

    load

    tree_data = @data.scan(/(\d+) .+?\0(.{20})/m).map { |mode, sha1| Object.const_get(MODES[mode]).new sha1 }

    check_common_data 'tree'

    tree_data.each &:check

    @@cache[:trees][@sha1] = true
  end
end

class Blob < GitObject
  @@cache[:blobs] = {}

  def check
    puts "Checking blob #{@sha1}..."

    if @@cache[:blobs][@sha1]
      puts "Skipped!"
      return
    end

    load

    check_common_data 'blob'

    @@cache[:blobs][@sha1] = true
  end
end

def run!
  head_ref_path   = File.read(File.join('.git/HEAD')).chomp[/\Aref: (.*)/, 1]
  branch_tip_sha1 = File.read(File.join('.git', head_ref_path)).chomp

  Commit.new(branch_tip_sha1).check
end

run! if __FILE__ == $0
