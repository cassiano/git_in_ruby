require 'yaml'
require 'logger'
require 'zlib'
require 'json'
require 'fileutils'

class RdbmsGitRepository < GitRepository
  attr_reader :environment, :dbconfig

  def initialize(options = {})
    super

    @environment = options[:environment] || 'development'
    @dbconfig    = YAML::load(File.open('config/database.yml'))[environment]

    ActiveRecord::Base.establish_connection(@dbconfig)

    default_log_file = File.join('log', "#{@environment}.log")
    FileUtils.rm(default_log_file, force: true) if !options[:log_to]
    ActiveRecord::Base.logger = Logger.new(options[:log_to] || default_log_file)
  end

  def head_commit_sha1
    DbRef.sha1_referenced_by 'HEAD'
  end

  def parse_object(raw_content)
    type, object = raw_content

    { type: type, size: object.size, data: object }
  end

  def parse_commit_data(data)
    {
      tree_sha1:      data[0],
      parents_sha1s:  data[1],
      author:         data[2],
      committer:      data[3],
      subject:        data[4]
    }
  end

  def parse_tree_data(data)
    { entries_info: data }
  end

  def load_object(sha1)
    raise MissingObjectError, "Object not found!" unless (object = DbObject.find_by(sha1: sha1))

    raw_content = object.to_raw

    parse_object(raw_content).merge content_sha1: sha1_from_raw_content(raw_content)
  end

  def create_commit_object!(tree, parents, author, committer, subject, cloned_from_sha1 = nil)
    data = format_commit_data(tree, parents, author, committer, subject)
    sha1 = sha1_from_raw_content([:commit, data])

    commit = DbCommit.create_with(
      tree:             db_object_for(data[0]),
      parents:          data[1].map { |parent| db_object_for(parent) },
      author:           data[2],
      committer:        data[3],
      subject:          data[4],
      cloned_from_sha1: cloned_from_sha1
    ).find_or_create_by(sha1: sha1)

    raise "Error when creating DbCommit: #{commit.errors.full_messages}. Data: #{data.inspect}." if !commit.errors.blank?

    sha1
  end

  def create_tree_object!(entries, cloned_from_sha1 = nil)
    data = format_tree_data(entries)
    sha1 = sha1_from_raw_content([:tree, data])

    tree = DbTree.create_with(
      entries: data.map do |entry|
        DbTreeEntry.new(
          filemode:   DbFilemode.find_or_create_by(mode: entry[0]),
          filename:   DbFilename.find_or_create_by(name: entry[1]),
          git_object: db_object_for(entry[2])
        )
      end,
      cloned_from_sha1: cloned_from_sha1
    ).find_or_create_by(sha1: sha1)

    raise "Error when creating DbTree: #{tree.errors.full_messages}. Entries: #{entries.inspect}." if !tree.errors.blank?

    sha1
  end

  def create_blob_object!(data, cloned_from_sha1 = nil)
    sha1 = sha1_from_raw_content([:blob, data])

    blob = DbBlob.create_with(
      data:             Zlib::Deflate.deflate(data),
      cloned_from_sha1: cloned_from_sha1
    ).find_or_create_by(sha1: sha1)

    raise "Error when creating DbBlob: #{blob.errors.full_messages}" if !blob.errors.blank?

    sha1
  end

  def update_branch!(name, commit_sha1)
    DbBranch.where(name: name).update_all(sha1: commit_sha1)
  end

  def branch_names
    DbBranch.all.map(&:name)
  end

  def find_cloned_git_object(original_object_sha1)
    (git_object = DbObject.find_by(cloned_from_sha1: original_object_sha1)) && git_object.sha1
  end

  private

  def format_commit_data(tree, parents, author, committer, subject)
    [
      sha1_for(tree),
      parents.map { |parent| sha1_for(parent) },
      author,
      committer,
      subject
    ]
  end

  def format_tree_data(entries)
    entries.map { |entry|
      [
        GitObject.mode_for_type(entry[0]),
        entry[1],
        sha1_for(entry[2])
      ]
    }
  end

  def sha1_from_raw_content(raw_content)
    Digest::SHA1.hexdigest raw_content.map { |item| String === item ? Base64.encode64(item) : item }.to_json
  end

  def db_object_for(db_object_or_sha1)
    DbObject === db_object_or_sha1 ? db_object_or_sha1 : DbObject.find_by!(sha1: db_object_or_sha1)
  end

  def sha1_for(db_object_or_sha1)
    DbObject === db_object_or_sha1 ? db_object_or_sha1.sha1 : db_object_or_sha1
  end

  remember :db_object_for
end
