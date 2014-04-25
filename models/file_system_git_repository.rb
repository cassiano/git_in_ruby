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

  def parse_commit_data(data)
    tree_sha1    = read_commit_data_row(data, 'tree')
    parents_sha1 = read_commit_data_rows(data, 'parent')
    author       = read_commit_data_row(data, 'author')
    committer    = read_commit_data_row(data, 'committer')
    subject      = read_subject_rows(data)

    {
      tree_sha1:    tree_sha1,
      parents_sha1: parents_sha1,
      author:       author.as_utf8 =~ /(.*) (\d+) ([+-]\d{4})/ && [$1, Time.at($2.to_i).utc, $3],
      committer:    committer && (committer.as_utf8 =~ /(.*) (\d+) ([+-]\d{4})/ && [$1, Time.at($2.to_i).utc, $3]),
      subject:      subject && subject.as_utf8
    }
  end

  def parse_tree_data(data)
    # Note: when analyzing and testing under different existing Git repositories, I have found distinct encodings being used in
    # filenames. For example: "\332ltimas_Not\355cias_das_Editorias_de_VEJA.com.html" (which is encoded using "ISO-8859-1") and
    # "U\314\201ltimas_Noti\314\201cias_das_Editorias_de_VEJA.com.html" (which uses "UTF-8"). For a real example check SHA1
    # a380c9bbea98259bd0f95162ab625c75e5636819 of project "veja-eleicoes-segundo-turno".
    entries_info = data.scan(/(\d+) ([^\0]+)\0([\x00-\xFF]{20})/).map do |mode, name, sha1|
      [[mode, name.as_utf8, sha1], mode.size + name.bytesize]
    end

    # Check if data contains any additional non-processed bytes.
    total_bytes = entries_info.map(&:last).inject(:+) + 22 * entries_info.size    # 22 = " ".size + "\0".size + sha1.size
    raise InvalidTreeData, "The tree contains invalid data (actual bytes: #{data.bytesize}, read bytes: #{total_bytes})" if total_bytes != data.bytesize

    { entries_info: entries_info.map(&:first) }
  end

  def load_object(sha1)
    path = File.join(git_path, 'objects', sha1[0..1], sha1[2..-1])

    raise MissingObjectError, "File '#{path}' not found! Have you unpacked all pack files?" unless File.exists?(path)

    raw_content = Zlib::Inflate.inflate(File.read(path))

    parse_object(raw_content).merge content_sha1: sha1_from_raw_content(raw_content)
  end

  def create_commit_object!(tree_sha1, parents_sha1, author, committer, subject, cloned_from_sha1 = nil)
    create_git_object! :commit, format_commit_data(tree_sha1, parents_sha1, author, committer, subject)
  end

  def create_tree_object!(entries, cloned_from_sha1 = nil)
    create_git_object! :tree, format_tree_data(entries)
  end

  def create_blob_object!(data, cloned_from_sha1 = nil)
    create_git_object! :blob, data || ''
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

  def format_commit_data(tree_sha1, parents_sha1, author, committer, subject)
    data = ""

    data << "tree #{tree_sha1}\n"
    data << parents_sha1.map { |sha1| "parent #{sha1}\n" }.join
    data << "author #{author[0]} #{author[1].to_i} #{author[2]}\n"
    data << "committer #{committer[0]} #{committer[1].to_i} #{committer[2]}\n"

    # Although sounding a little strange, I have found some existing Git repositories that contain blank commit subjects (see SHA1
    # 296fdc53bdd75147121aa290b4de0eeb3b4e7074 of the own Git source code repository for an example).
    if subject
      data << "\n"
      data << subject
    end
  end

  def format_tree_data(entries)
    entries.map { |entry|
      GitObject.mode_for_type(entry[0]) + ' ' + entry[1].dup.force_encoding('ASCII-8BIT') + "\0" + Sha1Util.byte_array_sha1(entry[2])
    }.join
  end

  def create_git_object!(type, data)
    header      = "#{type} #{data.bytesize}\0"
    raw_content = header + data
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

  # Fix bug found in SHA1 452ce291a99131768e2d61d2dcf8a4a1b78d39a3 of the Git source repo.
  def read_commit_data_rows(data, label)
    rows = data.split("\n")

    subject_rows_start_index = rows.index('')
    last_searched_row        = subject_rows_start_index ? subject_rows_start_index - 1 : -1

    # Return all rows containing the searched label, making sure we do not read data after the 1st empty row
    # (which usually contains a commit's subject).
    rows[0..last_searched_row].find_all { |row| row.split[0] == label }.map { |row| row[/\A\w+ (.*)/, 1] }
  end

  def read_subject_rows(data)
    subject_index = data.index("\n\n") + 2    # 2 = "\n\n".size

    puts ">>> [WARNING] Missing subject in commit." if !subject_index

    subject_index && data[subject_index..-1]
  end

  def sha1_from_raw_content(raw_content)
    Digest::SHA1.hexdigest raw_content
  end
end
