#!/usr/bin/env ruby

# To make sure all objects are "loose":
#
# 1) Move all pack files to a temp folder
# 2) For each pack file (.pack extensions), run: git unpack-objects < <pack>

require 'digest/sha1'
require 'zlib'
require 'fileutils'

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

module Memoize
  def remember(name)
    memory = {}

    original_method = instance_method(name)

    define_method(name) do |*args|
      memory[self.object_id] ||= {}

      if memory[self.object_id].has_key?(args)
        memory[self.object_id][args]
      else
        original = original_method.bind(self)

        memory[self.object_id][args] = original.call(*args)
      end
    end
  end
end

# List of possible exceptions.
class InvalidModeError          < StandardError; end
class InvalidSha1Error          < StandardError; end
class InvalidSizeError          < StandardError; end
class InvalidTypeError          < StandardError; end
class MissingObjectError        < StandardError; end
class ExcessiveCommitDataError  < StandardError; end
class MissingCommitDataError    < StandardError; end

class GitRepository
  attr_reader :project_path

  def initialize(project_path)
    @project_path = project_path
  end

  def head_commit
    @head_commit ||= Commit.find_or_initialize_by(self, head_commit_sha1)
  end

  def head_commit_sha1
    @head_commit_sha1 ||= begin
      head_ref_path = File.read(File.join(project_path, '.git', 'HEAD')).chomp[/\Aref: (.*)/, 1]
      File.read(File.join(project_path, '.git', head_ref_path)).chomp
    end
  end

  def head_fsck!
    head_commit.validate
  end
end

class GitObject
  extend Memoize

  attr_reader :repository, :sha1, :validated, :type, :raw_content, :header, :data, :size

  # http://stackoverflow.com/questions/737673/how-to-read-the-mode-field-of-git-ls-trees-output
  VALID_MODES = {
    '40000'  => 'Tree',
    '100644' => 'Blob',
    '100755' => 'ExecutableFile',
    '120000' => 'SymLink',
    '160000' => 'GitSubModule',
    '100664' => 'GroupWriteableFile'
  }

  SHA1_SIZE_IN_BYTES = 20

  @@instances = {}

  def self.find_or_initialize_by(repository, sha1, commit_level = 1)
    @@instances[sha1] ||= new(repository, standardized_sha1(sha1), commit_level)
  end

  def initialize(repository, sha1, commit_level)
    @repository   = repository
    @sha1         = sha1
    @commit_level = commit_level

    load
  end

  def validate
    puts "(#{@commit_level}) Validating #{self.class.name} with SHA1 #{@sha1} "

    # Locate the ancestor class which is the immediate subclass of GitObject in the hierarchy chain (one of: Blob, Commit or Tree).
    expected_type = (self.class.ancestors.find { |klass| klass.superclass == GitObject }).name.underscore.to_sym

    raw_content_sha1 = Digest::SHA1.hexdigest(@raw_content)

    raise InvalidTypeError.new(">>> Invalid type '#{@type}' (expected '#{expected_type}')") unless @type == expected_type
    raise InvalidSizeError.new(">>> Invalid size #{@size} (expected #{@data.size})") unless @size == @data.size
    raise InvalidSha1Error.new(">>> Invalid SHA1 '#{@sha1}' (expected '#{raw_content_sha1}')") unless @sha1 == raw_content_sha1
  end

  private

  def load
    path = File.join(@repository.project_path, '.git', 'objects', @sha1[0, 2], @sha1[2, SHA1_SIZE_IN_BYTES * 2 - 2])

    raise MissingObjectError.new(">>> File '#{path}' not found! Have you unpacked all pack files?") unless File.exists?(path)

    zlib_content          = File.read(path)
    @raw_content          = Zlib::Inflate.inflate(zlib_content)
    first_null_byte_index = @raw_content.index("\0")
    @header               = @raw_content[0...first_null_byte_index]
    @data                 = @raw_content[first_null_byte_index+1..-1]
    @type, @size          = @header =~ /(\w+) (\d+)/ && [$1.to_sym, $2.to_i]
  end

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
end

class Commit < GitObject
  attr_reader :tree, :author, :date, :subject

  def initialize(repository, sha1, commit_level)
    super

    @tree          = Tree.find_or_initialize_by(@repository, read_row('tree'), @commit_level)
    @author, @date = read_row('author') =~ /(.*) (\d+) [+-]\d{4}/ && [$1, Time.at($2.to_i)]
    @subject       = read_subject
  end

  def parents
    @parents ||= read_rows('parent').map { |sha1| Commit.find_or_initialize_by(@repository, sha1, @commit_level + 1) }
  end

  def validate
    super

    tree.validate
    parents.each &:validate
  end

  remember :validate

  def checkout!(destination_path = File.join('checkout_files', sha1))
    FileUtils.mkpath destination_path

    tree.checkout! destination_path
  end

  def changes_introduced_by
    tree.changes_between parents.map(&:tree)
  end

  private

  def read_row(label)
    rows = read_rows(label)

    if rows.size == 0
      raise MissingCommitDataError.new(">>> Missing #{label} in commit.")
    elsif rows.size > 1
      raise ExcessiveCommitDataError.new(">>> Excessive #{label} rows in commit.")
    end

    rows[0]
  end

  def read_rows(label)
    rows = @data.split("\n")

    rows.find_all { |row| row.split[0] == label }.map { |row| row[/\A\w+ (.*)/, 1] }
  end

  def read_subject
    rows = @data.split("\n")

    if !(empty_row_index = rows.index(''))
      raise MissingCommitDataError.new(">>> Missing subject in commit.")
    end

    rows[empty_row_index+1..-1].join("\n")
  end
end

class Tree < GitObject
  attr_reader :entries

  def initialize(repository, sha1, commit_level)
    super

    @entries = read_entries
  end

  def validate
    super

    entries.values.each &:validate
  end

  remember :validate

  def checkout!(destination_path = nil)
    entries.each do |name, entry|
      filename_or_path = destination_path ? File.join(destination_path, name) : name

      puts "Checking out #{filename_or_path}"

      case entry
        when ExecutableFile then                    # Must appear before its ancestors (e.g. Blob).
          File.write filename_or_path, entry.data
          File.chmod 0755, filename_or_path
        when Blob then
          File.write filename_or_path, entry.data
          File.chmod 0644, filename_or_path
        when Tree then
          puts "Creating folder #{filename_or_path}"

          FileUtils.mkpath filename_or_path
          entry.checkout! filename_or_path
        else
          puts "Skipping #{filename_or_path}..."
      end
    end
  end

  def changes_between(trees_to_compare, base_path = nil)
    entries.inject([]) do |changes, (name, entry)|
      filename_or_path = base_path ? File.join(base_path, name) : name

      if [Tree, Blob, ExecutableFile].include?(entry.class)
        entries_to_compare = trees_to_compare.map { |tree| tree.entries[name] }.compact

        if entries_to_compare.empty?
          added = true
        elsif !entries_to_compare.map(&:sha1).include?(entry.sha1)
          changed = true
        end

        if added || changed
          if Tree === entry
            changes.concat entry.changes_between(entries_to_compare.find_all { |e| Tree === e }, filename_or_path)
          else    # Blob or ExecutableFile
            changes << [filename_or_path, added ? :added : :changed]
          end
        end
      else
        puts "Skipping #{filename_or_path}..."
      end

      changes
    end
  end

  private

  def read_entries
    @data.scan(/(\d+) ([^\0]+)\0([\x00-\xFF]{20})/).inject({}) do |entries, (mode, name, sha1)|
      raise InvalidModeError.new(">>> Invalid mode #{mode} in file '#{name}'") unless VALID_MODES[mode]

      # Instantiate the object, based on its mode (Blob, Tree, ExecutableFile etc).
      entries.merge(name => Object.const_get(VALID_MODES[mode]).find_or_initialize_by(@repository, sha1, @commit_level))
    end
  end
end

class Blob < GitObject
  def validate
    super
  end

  remember :validate
end

class ExecutableFile < Blob
end

class SkippedFile < Blob
  def validate
  end
end

class SymLink < SkippedFile
end

class GitSubModule < SkippedFile
  def initialize(repository, sha1, commit_level)
    @repository   = repository
    @sha1         = sha1
    @commit_level = commit_level

    # Notice how we MUST NOT call the :load method for Git Sub Modules, otherwise the associated Git object won't be
    # found in the '.git/objects' folder, resulting in a MissingObjectError exception.
  end
end

class GroupWriteableFile < SkippedFile
end

def run!(project_path)
  repository = GitRepository.new(project_path)
  repository.head_fsck!
end

run! ARGV[0] || '.' if __FILE__ == $0
