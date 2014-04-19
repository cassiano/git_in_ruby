require 'yaml'
require 'logger'
require 'zlib'
require 'json'

class RdbmsGitRepository < GitRepository
  attr_reader :environment, :dbconfig

  def initialize(options = {})
    super

    @environment = options[:environment] || 'development'
    @dbconfig    = YAML::load(File.open('config/database.yml'))[environment]

    ActiveRecord::Base.establish_connection(@dbconfig)
    ActiveRecord::Base.logger = Logger.new(STDOUT)
  end

  def head_commit_sha1
    DbRef.sha1_referenced_by 'HEAD'
  end

  def parse_object(raw_content)
    type, object = raw_content

    { type: type, size: object.size, data: object }
  end

  def format_commit_data(tree, parents, author, committer, subject)
    [
      sha1_for(tree),
      parents.map { |parent| sha1_for(parent) }.sort,
      author,
      committer,
      subject
    ]
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
    entries.map { |entry|
      [
        GitObject.mode_for_type(entry[0]),
        entry[1],
        sha1_for(entry[2])
      ]
    }.sort_by { |entry| entry[1].downcase }
  end

  def parse_tree_data(data)
    { entries_info: data }
  end

  def load_object(sha1)
    raise MissingObjectError, "Object not found!" unless (object = DbObject.find_by_sha1(sha1))

    raw_content = object.to_raw

    parse_object(raw_content).merge content_sha1: sha1_from_raw_content(raw_content)
  end

  def create_commit_object!(data, cloned_from_sha1 = nil)
    sha1 = sha1_from_raw_content([:commit, data])

    DbCommit.create_with(
      tree:             db_object_for(data[0]),
      parents:          data[1].map { |parent| db_object_for(parent) },
      author:           data[2],
      committer:        data[3],
      subject:          data[4],
      cloned_from_sha1: cloned_from_sha1
    ).find_or_create_by(sha1: sha1)

    sha1
  end

  def create_tree_object!(data, cloned_from_sha1 = nil)
    sha1 = sha1_from_raw_content([:tree, data])

    DbTree.create_with(
      entries: data.map do |entry|
        DbTreeEntry.new(
          mode:       entry[0],
          name:       entry[1],
          git_object: db_object_for(entry[2])
        )
      end,
      cloned_from_sha1: cloned_from_sha1
    ).find_or_create_by(sha1: sha1)

    sha1
  end

  def create_blob_object!(data, cloned_from_sha1 = nil)
    sha1 = sha1_from_raw_content([:blob, data])

    DbBlob.create_with(
      data:             Zlib::Deflate.deflate(data),
      cloned_from_sha1: cloned_from_sha1
    ).find_or_create_by(sha1: sha1)

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
    Digest::SHA1.hexdigest raw_content.map { |item| String === item ? Base64.encode64(item) : item }.to_json
  end

  def db_object_for(db_object_or_sha1)
    DbObject === db_object_or_sha1 ? db_object_or_sha1 : DbObject.find_by_sha1(db_object_or_sha1)
  end

  def sha1_for(db_object_or_sha1)
    DbObject === db_object_or_sha1 ? db_object_or_sha1.sha1 : db_object_or_sha1
  end

  remember :db_object_for
end
