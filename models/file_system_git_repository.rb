# encoding: US-ASCII

require 'zlib'
require 'fileutils'

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
    data = ""
    data << "tree #{tree_sha1}\n"
    data << parents_sha1.map { |sha1| "parent #{sha1}\n" }.join
    data << "author #{author} #{Time.now.to_i} -0300\n"
    data << "committer #{committer} #{Time.now.to_i} -0300\n"
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

    # Returne all rows containing the searched label, making sure we do not read data after the 1st empty row
    # (which usually contains a commit's subject).
    rows[0...(rows.index('') || -1)].find_all { |row| row.split[0] == label }.map { |row| row[/\A\w+ (.*)/, 1] }
  end

  def read_subject_rows(data)
    rows = data.split("\n")

    raise MissingCommitDataError, "Missing subject in commit." unless (empty_row_index = rows.index(''))

    rows[empty_row_index+1..-1].join("\n")
  end
end