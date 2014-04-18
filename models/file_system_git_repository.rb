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
    committer = read_commit_data_row(data, 'committer', false)
    subject   = read_subject_rows(data, false)

    {
      tree_sha1:    read_commit_data_row(data, 'tree'),
      parents_sha1: read_commit_data_rows(data, 'parent'),
      author:       read_commit_data_row(data, 'author').find_and_apply_valid_encoding =~ /(.*) (\d+) [+-]\d{4}/ && [$1, Time.at($2.to_i)],
      committer:    committer && (committer.find_and_apply_valid_encoding =~ /(.*) (\d+) [+-]\d{4}/ && [$1, Time.at($2.to_i)]),
      subject:      subject && subject.find_and_apply_valid_encoding
    }
  end

  def format_tree_data(entries)
    entries.map { |entry|
      GitObject.mode_for_type(entry[0]) + ' ' + entry[1].dup.force_encoding('ASCII-8BIT') + "\0" + Sha1Util.byte_array_sha1(entry[2])
    }.join
  end

  def parse_tree_data(data)
    # Note: when analyzing and testing under different existing Git repositories, I have found distinct encodings being used in
    # filenames. For example: "\332ltimas_Not\355cias_das_Editorias_de_VEJA.com.html" (which is encoded using "ISO-8859-1") and
    # "U\314\201ltimas_Noti\314\201cias_das_Editorias_de_VEJA.com.html" (which uses "UTF-8"). For a real example check SHA1
    # a380c9bbea98259bd0f95162ab625c75e5636819 of project "veja-eleicoes-segundo-turno".
    entries_info = data.scan(/(\d+) ([^\0]+)\0([\x00-\xFF]{20})/).map do |mode, name, sha1|
      [mode, name.find_and_apply_valid_encoding, sha1]
    end

    total_bytes = entries_info.inject(0) do |sum, (mode, name, _)|
      sum + mode.size + name.bytesize + 22   # 22 = " ".size + "\0".size + sha1.size
    end

    # Check if data contains any additional non-processed bytes.
    raise InvalidTreeData, 'The tree contains invalid data' if total_bytes != data.bytesize

    { entries_info: entries_info }
  end

  def load_object(sha1)
    path = File.join(git_path, 'objects', sha1[0..1], sha1[2..-1])

    raise MissingObjectError, "File '#{path}' not found! Have you unpacked all pack files?" unless File.exists?(path)

    raw_content = Zlib::Inflate.inflate(File.read(path))

    parse_object(raw_content).merge content_sha1: sha1_from_raw_content(raw_content)
  end

  def create_commit_object!(data, clone_sha1 = nil)
    create_git_object! :commit, data
  end

  def create_tree_object!(data, clone_sha1 = nil)
    create_git_object! :tree, data
  end

  def create_blob_object!(data, clone_sha1 = nil)
    create_git_object! :blob, data
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

  def create_git_object!(type, data)
    header      = "#{type} #{data.bytesize}\0"
    raw_content = header + (data || '')
    sha1        = sha1_from_raw_content(raw_content)
    path        = File.join(git_path, 'objects', sha1[0..1], sha1[2..-1])

    unless File.exists?(path)
      zipped_content = Zlib::Deflate.deflate(raw_content)

      FileUtils.mkpath File.dirname(path)
      File.write path, zipped_content
    end

    sha1
  end

  def read_commit_data_row(data, label, required = true)
    rows = read_commit_data_rows(data, label)

    if rows.size == 0 && required
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

  def read_subject_rows(data, required = true)
    rows = data.split("\n")

    raise MissingCommitDataError, "Missing subject in commit." if required and !(empty_row_index = rows.index(''))

    empty_row_index && rows[empty_row_index+1..-1].join("\n")
  end

  def time_offset_for_commit(seconds)
    sign = seconds < 0 ? '-' : '+'
    hour   = seconds.abs / 3600
    minute = (seconds.abs - hour * 3600) / 60

    '%1s%02d%02d' % [sign, hour, minute]
  end

  def sha1_from_raw_content(raw_content)
    Digest::SHA1.hexdigest raw_content
  end
end
