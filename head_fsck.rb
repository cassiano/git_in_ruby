#!/usr/bin/env ruby

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

###############################
# List of possible exceptions.
###############################

class InvalidModeError          < StandardError; end
class InvalidSha1Error          < StandardError; end
class InvalidSizeError          < StandardError; end
class InvalidTypeError          < StandardError; end
class MissingObjectError        < StandardError; end
class MissingTreeInCommitError  < StandardError; end

class GitRepository
  attr_reader :project_path

  SHA1_SIZE_IN_BYTES = 20

  def initialize(project_path)
    @project_path = project_path
  end

  def head_commit_sha1
    head_ref_path = File.read(File.join(project_path, '.git', 'HEAD')).chomp[/\Aref: (.*)/, 1]

    File.read(File.join(project_path, '.git', head_ref_path)).chomp
  end

  def read_object_content(git_object)
    path = File.join(project_path, '.git', 'objects', git_object.sha1[0, 2], git_object.sha1[2, SHA1_SIZE_IN_BYTES * 2 - 2])

    raise MissingObjectError.new("\n>>> File '#{path}' not found! Have you unpacked all pack files?") unless File.exists?(path)

    zlib_content          = File.read(path)
    raw_content           = Zlib::Inflate.inflate(zlib_content)
    first_null_byte_index = raw_content.index("\0")
    header                = raw_content[0...first_null_byte_index]
    data                  = raw_content[(first_null_byte_index + 1)..-1]
    type, size            = header.split

    git_object.type             = type
    git_object.size             = size.to_i
    git_object.raw_content_sha1 = Digest::SHA1.hexdigest(raw_content)
    git_object.data             = data if [:commit, :tree].include?(type.to_sym)
    git_object.data_size        = data.size
  end

  def head_fsck
    head_commit = Commit.find_or_initialize_by(self, self.head_commit_sha1)
    head_commit.validate
  end
end

class GitObject
  attr_reader :repository, :sha1, :validated
  attr_accessor :type, :size, :raw_content_sha1, :data, :data_size

  # http://stackoverflow.com/questions/737673/how-to-read-the-mode-field-of-git-ls-trees-output
  VALID_MODES = {
    '40000'  => 'Tree',
    '100644' => 'Blob',
    '100755' => 'ExecutableFile',
    '120000' => 'SymLink',
    '160000' => 'GitSubModule',
    '100664' => 'GroupWriteableFile'
  }

  @@instances = {}

  def self.find_or_initialize_by(repository, sha1, commit_level = 1)
    sha1 = case sha1.size
      when 20 then hex_string_sha1(sha1)
      when 40 then sha1
      else raise "\n>>> Invalid SHA1 size (#{sha1.size})"
    end

    @@instances[sha1] ||= new(repository, sha1, commit_level)
  end

  def self.hex_string_sha1(byte_sha1)
    byte_sha1.bytes.map { |b| "%02x" % b }.join
  end

  def initialize(repository, sha1, commit_level)
    @repository   = repository
    @sha1         = sha1
    @commit_level = commit_level
    @validated    = false

    repository.read_object_content self
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

  private

  def check_content
    expected_types = (self.class.ancestors - GitObject.ancestors).map { |klass| klass.name.underscore }

    raise InvalidTypeError.new("\n>>> Invalid type '#{@type}' (expected one of [#{expected_types.join(', ')}])") unless expected_types.include?(@type)
    raise InvalidSizeError.new("\n>>> Invalid size #{@size} (expected #{@data_size})") unless @size == @data_size
    raise InvalidSha1Error.new("\n>>> Invalid SHA1 '#{@sha1}' (expected '#{@raw_content_sha1}')") unless @sha1 == @raw_content_sha1

    check_data if respond_to?(:check_data)
  end
end

class Commit < GitObject
  def check_data
    lines = @data.split("\n")

    if (tree_line = lines.find { |line| line.split[0] == 'tree' })
      tree_sha1 = tree_line.split[1]
    else
      raise MissingTreeInCommitError.new("\n>>> Missing required tree in commit.")
    end

    @tree = Tree.find_or_initialize_by(@repository, tree_sha1, @commit_level)

    @parents = lines.find_all { |line| line.split[0] == 'parent' }.map do |line|
      commit_sha1 = line.split[1]

      Commit.find_or_initialize_by @repository, commit_sha1, @commit_level + 1
    end

    @tree.validate
    @parents.each &:validate
  end
end

class Tree < GitObject
  def check_data
    @entries = @data.scan(/(\d+) (.+?)\0([\x00-\xFF]{20})/).map do |mode, name, sha1|
      raise InvalidModeError.new("\n>>> Invalid mode #{mode} in file '#{name}'") unless VALID_MODES[mode]

      print "\n  #{name}"

      # Instantiate the object, based on its mode (Blob, Tree, ExecutableFile etc).
      Object.const_get(VALID_MODES[mode]).find_or_initialize_by @repository, sha1, @commit_level
    end

    @entries.each &:validate
  end
end

class Blob < GitObject
end

class ExecutableFile < Blob
end

class SkippedFile < Blob
  def initialize(repository, sha1, commit_level)
    @repository   = repository
    @sha1         = sha1
    @commit_level = commit_level
    @validated    = true          # Indicate the file has already been validated, so it can be safely skipped.
  end
end

class SymLink < SkippedFile
end

class GitSubModule < SkippedFile
end

class GroupWriteableFile < SkippedFile
end

def run!(project_path)
  repository = GitRepository.new(project_path)
  repository.head_fsck
end

run! ARGV[0] || '.' if __FILE__ == $0
