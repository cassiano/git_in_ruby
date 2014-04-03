# encoding: US-ASCII

#!/usr/bin/env ruby

# To make sure all objects are "loose":
#
# 1) Move all pack files to a temp folder
# 2) For each pack file (.pack extensions), run: git unpack-objects < <pack>

require 'digest/sha1'
require 'zlib'
require 'fileutils'
# require 'debug'

require File.join(File.dirname(File.expand_path(__FILE__)), 'memoize')
require File.join(File.dirname(File.expand_path(__FILE__)), 'sha1_util')
require File.join(File.dirname(File.expand_path(__FILE__)), 'string_extensions')

# List of possible exceptions.
class InvalidModeError          < StandardError; end
class InvalidSha1Error          < StandardError; end
class InvalidSizeError          < StandardError; end
class InvalidTypeError          < StandardError; end
class MissingObjectError        < StandardError; end
class ExcessiveCommitDataError  < StandardError; end
class MissingCommitDataError    < StandardError; end
class InvalidTreeData           < StandardError; end

class GitRepository
  extend Memoize

  attr_reader :instances

  def initialize(options = {})
    options = {
      bare_repository: false
    }.merge(options)

    @instances       = {}
    @bare_repository = !!options[:bare_repository]
  end

  def bare_repository?
    @bare_repository
  end

  def head_commit(options = {})
    Commit.find_or_initialize_by_sha1 self, head_commit_sha1, options
  end

  def head_fsck
    head_commit.validate
  end

  def head_commit_sha1
    raise NotImplementedError
  end

  def load_object(sha1)
    raise NotImplementedError
  end

  # Must return a hash with the following keys: type, size and data.
  def parse_object(raw_content)
    raise NotImplementedError
  end

  def create_commit!(branch_name, tree_sha1, parents_sha1, author, committer, subject)
    data        = format_commit_data(tree_sha1, parents_sha1, author, committer, subject)
    commit_sha1 = create_git_object!(:commit, data)

    update_branch! branch_name, commit_sha1

    commit_sha1
  end

  def create_tree!(entries)
    data = format_tree_data(entries)

    create_git_object! :tree, data
  end

  def create_blob!(data)
    create_git_object! :blob, data
  end

  def parse_commit_data(commit)
    raise NotImplementedError
  end

  def parse_tree_data(tree)
    raise NotImplementedError
  end

  def update_branch!(name, commit_sha1)
    raise NotImplementedError
  end

  def branches
    raise NotImplementedError
  end

  protected

  def create_git_object!(type, data)
    raise NotImplementedError
  end

  # Should generate a format suitable for consumption by both the :parse_commit_data and create_git_object methods.
  def format_commit_data(tree_sha1, parents_sha1, author, committer, subject)
    raise NotImplementedError
  end

  # Should generate a format suitable for consumption by both the :parse_tree_data and create_git_object methods.
  def format_tree_data(entries)
    raise NotImplementedError
  end

  remember :head_commit_sha1
end

class FileSystemGitRepository < GitRepository
  attr_reader :project_path

  def initialize(options = {})
    super

    @project_path = options[:project_path]
  end

  def git_path
    bare_repository? ? project_path : File.join(project_path, '.git')
  end

  def head_commit_sha1
    head_ref_path = File.read(File.join(git_path, 'HEAD')).chomp[/\Aref: (.*)/, 1]

    File.read(File.join(git_path, head_ref_path)).chomp
  end

  def parse_object(raw_content)
    first_null_byte_index = raw_content.index("\0")
    header                = raw_content[0...first_null_byte_index]
    type, size            = header =~ /(\w+) (\d+)/ && [$1.to_sym, $2.to_i]
    data                  = raw_content[first_null_byte_index+1..-1]

    { type: type, size: size, data: data }
  end

  def format_commit_data(tree_sha1, parents_sha1, author, committer, subject)
    current_time                 = Time.now
    current_time_seconds_elapsed = current_time.to_i                                  # Seconds elapsed since 01/Jan/1970 00:00:00.
    current_time_utc_offset      = time_offset_for_commit(current_time.utc_offset)    # Should range from '-2359' to '+2359'.

    data = ""
    data << "tree #{tree_sha1}\n"
    data << parents_sha1.map { |sha1| "parent #{sha1}\n" }.join
    data << "author #{author} #{current_time_seconds_elapsed} #{current_time_utc_offset}\n"
    data << "committer #{committer} #{current_time_seconds_elapsed} #{current_time_utc_offset}\n"
    data << "\n"
    data << subject + "\n"
  end

  def parse_commit_data(data)
    {
      tree_sha1:    read_commit_data_row(data, 'tree'),
      parents_sha1: read_commit_data_rows(data, 'parent'),
      author:       read_commit_data_row(data, 'author')     =~ /(.*) (\d+) [+-]\d{4}/ && [$1, Time.at($2.to_i)],
      committer:    read_commit_data_row(data, 'committer')  =~ /(.*) (\d+) [+-]\d{4}/ && [$1, Time.at($2.to_i)],
      subject:      read_subject_rows(data)
    }
  end

  def format_tree_data(entries)
    entries.map { |entry|
      GitObject.mode_for_type(entry[0]) + " " + entry[1] + "\0" + Sha1Util.byte_array_sha1(entry[2])
    }.join
  end

  def parse_tree_data(data)
    entries_info = data.scan(/(\d+) ([^\0]+)\0([\x00-\xFF]{20})/)

    total_bytes = entries_info.inject(0) do |sum, (mode, name, _)|
      sum + mode.size + name.size + 22   # 22 = " ".size + "\0".size + sha1.size
    end

    # Check if data contains any additional non-processed bytes.
    raise InvalidTreeData, 'The tree contains invalid data' if total_bytes != data.size

    { entries_info: entries_info }
  end

  def load_object(sha1)
    path = File.join(git_path, 'objects', sha1[0..1], sha1[2..-1])

    raise MissingObjectError, "File '#{path}' not found! Have you unpacked all pack files?" unless File.exists?(path)

    raw_content = Zlib::Inflate.inflate File.read(path)

    parse_object(raw_content).merge content_sha1: Digest::SHA1.hexdigest(raw_content)
  end

  def create_git_object!(type, data)
    header      = "#{type} #{data.size}\0"
    raw_content = header + data
    sha1        = Digest::SHA1.hexdigest(raw_content)
    path        = File.join(git_path, 'objects', sha1[0..1], sha1[2..-1])

    unless File.exists?(path)
      zipped_content = Zlib::Deflate.deflate(raw_content)

      FileUtils.mkpath File.dirname(path)
      File.write path, zipped_content
    end

    sha1
  end

  def update_branch!(name, commit_sha1)
    File.write File.join(git_path, 'refs', 'heads', name), commit_sha1 + "\n"
  end

  def branch_names
    names = Dir.entries(File.join(git_path, 'refs', 'heads'))
    names.delete('.')
    names.delete('..')

    names
  end

  private

  def read_commit_data_row(data, label)
    rows = read_commit_data_rows(data, label)

    if rows.size == 0
      raise MissingCommitDataError, "Missing #{label} in commit."
    elsif rows.size > 1
      raise ExcessiveCommitDataError, "Excessive #{label} rows in commit."
    end

    rows[0]
  end

  def read_commit_data_rows(data, label)
    rows = data.split("\n")

    # Return all rows containing the searched label, making sure we do not read data after the 1st empty row
    # (which usually contains the commit's subject).
    rows[0...(rows.index('') || -1)].find_all { |row| row.split[0] == label }.map { |row| row[/\A\w+ (.*)/, 1] }
  end

  def read_subject_rows(data)
    rows = data.split("\n")

    raise MissingCommitDataError, "Missing subject in commit." unless (empty_row_index = rows.index(''))

    rows[empty_row_index+1..-1].join("\n")
  end

  def time_offset_for_commit(seconds)
    sign   = seconds < 0 ? '-' : '+'
    hour   = seconds.abs / 3600
    minute = (seconds.abs - hour * 3600) / 60

    '%1s%02d%02d' % [sign, hour, minute]
  end
end

class MemoryGitRepository < GitRepository
  attr_reader :branches, :head, :objects

  def initialize(options = {})
    super

    @branches = {}
    @head     = 'master'
    @objects  = {}
  end

  def head_commit_sha1
    branches[head]
  end

  def parse_object(raw_content)
    { type: raw_content[0], size: raw_content[1], data: raw_content[2] }
  end

  def format_commit_data(tree_sha1, parents_sha1, author, committer, subject)
    [tree_sha1, parents_sha1, author, committer, subject]
  end

  def parse_commit_data(data)
    {
      tree_sha1:    data[0],
      parents_sha1: data[1],
      author:       data[2],
      committer:    data[3],
      subject:      data[4]
    }
  end

  def format_tree_data(entries)
    entries.map { |entry| [GitObject.mode_for_type(entry[0]), entry[1], entry[2]] }
  end

  def parse_tree_data(data)
    { entries_info: data }
  end

  def load_object(sha1)
    raise MissingObjectError, "Object not found!" unless objects[sha1]

    raw_content = objects[sha1]

    parse_object(raw_content).merge content_sha1: sha1_from_raw_content(raw_content)
  end

  def create_git_object!(type, data)
    raw_content = [type, data.size, data]
    sha1        = sha1_from_raw_content(raw_content)

    objects[sha1] ||= raw_content

    sha1
  end

  def update_branch!(name, commit_sha1)
    branches[name] = commit_sha1
  end

  def branch_names
    branches.keys
  end

  private

  def sha1_from_raw_content(raw_content)
    Digest::SHA1.hexdigest raw_content.map(&:to_s).join("\n")
  end
end

require 'active_record'
require 'yaml'
require 'logger'

class DbBranch < ActiveRecord::Base
  validates_presence_of :name, :sha1
end

class DbRef < ActiveRecord::Base
  validates_presence_of :name, :ref
end

class DbObject < ActiveRecord::Base
  validates_presence_of :sha1, :type
end

class DbBlob < DbObject
end

class DbTree < DbObject
  has_many :entries, class_name: 'DbTreeEntry', foreign_key: :tree_id
end

class DbTreeEntry < ActiveRecord::Base
  validates_presence_of :mode, :name, :entry    # Do not include :tree in this list!

  belongs_to :tree, class_name: 'DbTree'
  belongs_to :entry, class_name: 'DbObject'      # DbTree or DbBlob.
end

class DbCommit < DbObject
  belongs_to              :tree, class_name: 'DbTree', foreign_key: :commit_tree_id
  has_and_belongs_to_many :parents,
                          class_name: 'DbCommit',
                          join_table: :db_commit_parents,
                          foreign_key: :commit_id,
                          association_foreign_key: :parent_id

  validates_presence_of :tree, :commit_author, :commit_committer, :commit_subject
end

class RdbmsGitRepository < GitRepository
  DATABASE_ENV = ENV['DATABASE_ENV'] || 'development'

  def initialize(options = {})
    super

    dbconfig = YAML::load(File.open('config/database.yml'))[DATABASE_ENV]

    ActiveRecord::Base.establish_connection(dbconfig)
    ActiveRecord::Base.logger = Logger.new(STDOUT)
  end

  def head_commit_sha1
    head_ref = DbRef.find_by_name('HEAD')

    DbBranch.find_by_name(head_ref.ref).sha1
  end

  def parse_object(object)
    case object
      when DbBlob then
        data = object.blob_data

        { type: :blob, size: data.size, data: data }
      when DbTree then
        data = object.entries.map { |entry| [entry.mode, entry.name, entry.entry.sha1] }

        { type: :tree, size: data.size, data: data }
      when DbCommit then
        data = [object.tree.sha1, object.parents.map(&:sha1), object.commit_author, object.commit_committer, object.commit_subject]

        { type: :commit, size: data.size, data: data }
      else
        raise "Unexpected object type (#{object.type}."
    end
  end

  def format_commit_data(tree_sha1, parents_sha1, author, committer, subject)
    [tree_sha1, parents_sha1, author, committer, subject]
  end

  def parse_commit_data(data)
    {
      tree_sha1:    data[0],
      parents_sha1: data[1],
      author:       data[2],
      committer:    data[3],
      subject:      data[4]
    }
  end

  def format_tree_data(entries)
    entries.map { |entry| [GitObject.mode_for_type(entry[0]), entry[1], entry[2]] }
  end

  def parse_tree_data(data)
    { entries_info: data }
  end

  def load_object(sha1)
    raise MissingObjectError, "Object not found!" unless (raw_content = DbObject.find_by_sha1(sha1))

    parse_object(raw_content).merge content_sha1: sha1_from_raw_content(raw_content)
  end

  def create_git_object!(type, data)
    raw_content = [type, data]
    sha1        = sha1_from_raw_content(raw_content)

    case type
      when :blob then
        DbBlob.create_with(
          blob_data:  data
        ).find_or_create_by(sha1: sha1)
      when :tree then
        DbTree.create_with(
          entries: data.map do |entry|
            DbTreeEntry.new mode: entry[0], name: entry[1], entry: db_object_for(entry[2])
          end
        ).find_or_create_by(sha1: sha1)
      when :commit then
        DbCommit.create_with(
          tree:             db_object_for(data[0]),
          parents:          data[1].map { |db_commit_or_sha1| db_object_for(db_commit_or_sha1) },
          commit_author:    data[2],
          commit_committer: data[3],
          commit_subject:   data[4]
        ).find_or_create_by(sha1: sha1)
    end

    sha1
  end

  def update_branch!(name, commit_sha1)
    DbBranch.where(name: name).update_all(sha1: commit_sha1)
  end

  def branch_names
    DbBranch.all.map(&:name)
  end

  private

  def sha1_from_raw_content(raw_content)
    Digest::SHA1.hexdigest raw_content.inspect
  end

  def db_object_for(db_object_or_sha1)
    DbObject === db_object_or_sha1 ? db_object_or_sha1 : DbObject.find_by_sha1(db_object_or_sha1)
  end
end

class GitObject
  extend Memoize

  attr_reader :repository, :sha1, :commit_level, :type, :size, :data, :content_sha1

  # http://stackoverflow.com/questions/737673/how-to-read-the-mode-field-of-git-ls-trees-output
  VALID_MODES = {
    '40000'  => 'Tree',
    '100644' => 'Blob',
    '100755' => 'ExecutableFile',
    '100664' => 'GroupWriteableFile',
    '120000' => 'SymLink',
    '160000' => 'GitSubModule'
  }

  def self.find_or_initialize_by_sha1(repository, sha1, options = {})
    repository.instances[sha1] ||= new(repository, Sha1Util.standardized_hex_string_sha1(sha1), options)
  end

  def initialize(repository, sha1, options = {})
    options = {
      commit_level: 1,
      load_blob_data: false
    }.merge(options)

    @repository     = repository
    @sha1           = sha1
    @commit_level   = options[:commit_level]
    @load_blob_data = !!options[:load_blob_data]

    load
  end

  def load_blob_data?
    @load_blob_data
  end

  def validate
    puts "(#{commit_level}) Validating #{self.class.name} with SHA1 #{sha1}"

    # Locate the ancestor class which is the immediate subclass of GitObject in the hierarchy chain (one of: Blob, Commit or Tree).
    expected_type = (self.class.ancestors.find { |cls| cls.superclass == GitObject }).name.underscore.to_sym

    raise InvalidTypeError, "Invalid type '#{type}' (expected '#{expected_type}')"  unless type == expected_type
    raise InvalidSha1Error, "Invalid SHA1 '#{sha1}' (expected '#{content_sha1}')"   unless sha1 == content_sha1

    validate_data
  end

  def validate_data
    raise NotImplementedError
  end

  def self.mode_for_type(type)
    VALID_MODES.inject({}) { |acc, (mode, object_type)| acc.merge object_type.underscore.to_sym => mode }[type]
  end

  protected

  def parse_data(data)
  end

  def load
    object_info = repository.load_object(sha1)

    data = object_info[:data]
    size = object_info[:size]

    @content_sha1 = object_info[:content_sha1]
    @type         = object_info[:type]
    @size         = size
    @data         = data unless type == :blob && !load_blob_data?

    parse_data(data) if data

    # Since the data will not always be available, its size must be checked here (and not later, in the :validate method).
    raise InvalidSizeError, "Invalid size #{size} (expected #{data.size})" unless size == data.size
  end
end

class Commit < GitObject
  attr_reader :tree_sha1, :parents_sha1, :subject, :author, :committer

  def tree
    Tree.find_or_initialize_by_sha1 repository, tree_sha1, commit_level: commit_level, load_blob_data: load_blob_data?
  end

  def parents
    parents_sha1.map do |sha1|
      Commit.find_or_initialize_by_sha1(repository, sha1, commit_level: commit_level + 1, load_blob_data: load_blob_data?)
    end
  end

  def parent
    if parents.size == 0
      nil
    elsif parents.size == 1
      parents[0]
    else
      raise "More than one parent commit found."
    end
  end

  def validate_data
    tree.validate
    parents.each &:validate
  end

  def checkout!(destination_path = File.join('checkout_files', sha1[0..6]))
    FileUtils.mkpath destination_path
    tree.checkout! destination_path
  end

  def changes_introduced_by
    updates_and_creations = tree.changes_between(parents.map(&:tree))

    # Find deletions between the current commit and its parents by finding the *common* additions the other way around, i.e.
    # between each of the parents and the current commit, then transforming them into deletions.
    deletions = parents.map { |parent|
      parent.tree.changes_between([tree]).find_all { |(_, action, _)| action == :created }.map { |name, _, sha1s| [name, :deleted, sha1s.reverse] }
    }.inject(:&) || []
    updates_and_creations.concat deletions

    # Identify renamed files, replacing the :created and :deleted associated pair by a single :renamed one.
    updates_and_creations.find_all { |(_, action, _)| action == :deleted }.inject(updates_and_creations) { |changes, deleted_file|
      if (created_file = changes.find { |(_, action, (_, created_sha1))| action == :created && created_sha1 == deleted_file[2][0] })
        changes.delete created_file
        changes.delete deleted_file
        changes << ["#{deleted_file[0]} -> #{created_file[0]}", :renamed, [deleted_file[2][0], created_file[2][1]]]
      end

      changes
    }
  end

  protected

  def parse_data(data)
    parsed_data = repository.parse_commit_data(data)

    @tree_sha1    = parsed_data[:tree_sha1]
    @parents_sha1 = parsed_data[:parents_sha1]
    @author       = parsed_data[:author]
    @committer    = parsed_data[:committer]
    @subject      = parsed_data[:subject]
  end

  remember :tree, :parents, :validate
end

class Tree < GitObject
  attr_reader :entries_info

  def entries
    entries_info.inject({}) do |items, (mode, name, sha1)|
      raise InvalidModeError, "Invalid mode #{mode} in file '#{name}'" unless VALID_MODES[mode]

      # Instantiate the object, based on its mode (Blob, Tree, ExecutableFile etc).
      items.merge name => Object.const_get(VALID_MODES[mode]).find_or_initialize_by_sha1(
        repository, sha1, commit_level: commit_level, load_blob_data: load_blob_data?
      )
    end
  end

  def validate_data
    entries.values.each &:validate
  end

  def checkout!(destination_path = nil)
    entries.each do |name, entry|
      filename_or_path = destination_path ? File.join(destination_path, name) : name

      puts "Checking out #{filename_or_path}"

      case entry
        when ExecutableFile, GroupWriteableFile, Blob then
          filemode = { ExecutableFile => 0755, GroupWriteableFile => 0664, Blob => 0644 }[entry.class]

          File.write filename_or_path, entry.data
          File.chmod filemode, filename_or_path
        when Tree then
          puts "Creating folder #{filename_or_path}"

          FileUtils.mkpath filename_or_path
          entry.checkout! filename_or_path
        else
          puts "Skipping #{filename_or_path}..."
      end
    end
  end

  def changes_between(other_trees, base_path = nil)
    entries.inject([]) do |changes, (name, entry)|
      filename_or_path = base_path ? File.join(base_path, name) : name

      if [Tree, Blob, ExecutableFile, GroupWriteableFile].include?(entry.class)
        other_entries = other_trees.map { |tree| tree.entries[name] }.compact

        # For merge rules, check: http://thomasrast.ch/git/evil_merge.html
        if other_entries.empty?
          action = :created
          sha1s  = [[], entry.sha1[0..6]]
        elsif !other_entries.map(&:sha1).include?(entry.sha1)
          action = :updated
          sha1s  = [other_entries.map { |e| e.sha1[0..6] }.compact.uniq, entry.sha1[0..6]]
        end

        if action   # A nil action indicates an unchanged file.
          if Tree === entry
            changes.concat entry.changes_between(other_entries.find_all { |e| Tree === e }, filename_or_path)
          else    # Blob or one of its subclasses.
            changes << [filename_or_path, action, sha1s]
          end
        end
      else
        puts "Skipping #{filename_or_path}..."
      end

      changes
    end
  end

  protected

  def parse_data(data)
    parsed_data = repository.parse_tree_data(data)

    @entries_info = parsed_data[:entries_info]
  end

  remember :entries, :changes_between, :validate
end

class Blob < GitObject
  def validate_data
  end

  remember :validate
end

class ExecutableFile < Blob
end

class GroupWriteableFile < Blob
end

class SymLink < Blob
end

class GitSubModule < Blob
  def load
  end

  def validate
  end
end

def run!(project_path, bare_repository)
  repository = FileSystemGitRepository.new(project_path: project_path, bare_repository: bare_repository)
  repository.head_fsck
end

# $enable_tracing = false
# $trace_out = open('/tmp/trace.txt', 'w')
#
# set_trace_func proc { |event, file, line, id, binding, classname|
#   if $enable_tracing && event == 'call'
#     $trace_out.puts "#{file}:#{line} #{classname}##{id}"
#   end
# }
#
# $enable_tracing = true

run! ARGV[0] || '.', ARGV[1] && ARGV[1].downcase == 'bare' if __FILE__ == $0
