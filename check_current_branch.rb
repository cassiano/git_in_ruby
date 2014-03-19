# To make sure all objects are "loose":
#
# 1) Move all pack files to a temp folder
# 2) For each pack file (.pack extensions), run: git unpack-objects < <pack>

require 'digest/sha1'
require 'zlib'

BLOB_MODE            = '100644'
TREE_MODE            = '40000'
EXECUTABLE_FILE_MODE = '100755'
SYM_LINK_MODE        = '120000'
SHA1_SIZE_IN_BYTES   = 20

def run!
  head_ref_path   = File.read(File.join('.git/HEAD')).chomp[/\Aref: (.*)/, 1]
  branch_tip_hash = File.read(File.join('.git', head_ref_path)).chomp

  check_commit branch_tip_hash
end

def read_git_object(sha1)
  path = File.join('.git/objects/', sha1[0, 2], sha1[2, SHA1_SIZE_IN_BYTES * 2 - 2])

  raise ">>> File #{path} not found" unless File.exists?(path)

  zlib_content = File.read(path)
  raw_content  = Zlib::Inflate.inflate(zlib_content)
  header       = raw_content.split("\0")[0]
  data         = raw_content[(header.size + 1)..-1]
  type, size   = header.split
  size         = size.to_i

  [type, size, data, raw_content]
end

def check_commit(commit_sha1)
  puts "Checking commit #{commit_sha1}"

  @commits_already_checked ||= {}

  if @commits_already_checked[commit_sha1]
    puts "[commit already checked]"
    return
  end

  commit       = read_git_object(commit_sha1)
  commit_data  = commit[2].split("\n")
  tree_sha1    = commit_data.find { |line| line.split[0] == 'tree' }.split[1]
  parents_sha1 = commit_data.find_all { |line| line.split[0] == 'parent' }.map { |line| line.split[1] }

  raise ">>> Invalid type '#{commit[0]}' (expected 'commit')" unless commit[0] == 'commit'
  raise ">>> Invalid size #{commit[1]} (expected #{commit[2].size})" unless commit[1] == commit[2].size
  raise ">>> Invalid SHA1 '#{Digest::SHA1.hexdigest(commit[3])}' (expected '#{commit_sha1}')" unless Digest::SHA1.hexdigest(commit[3]) == commit_sha1

  check_tree(tree_sha1)
  parents_sha1.each { |sha1| check_commit(sha1) }

  @commits_already_checked[commit_sha1] = true
end

def check_tree(tree_sha1)
  puts "Checking tree #{tree_sha1}"

  @trees_already_checked ||= {}

  if @trees_already_checked[tree_sha1]
    puts "[tree already checked]"
    return
  end

  tree = read_git_object(tree_sha1)

  # tree_data = tree[2].scan(/(#{[BLOB_MODE, TREE_MODE, EXECUTABLE_FILE_MODE, SYM_LINK_MODE].join('|')}) (.+?)\0(.{20})/m).map do |type, name, sha1|
  tree_data = tree[2].scan(/(\d+) (.+?)\0(.{20})/m).map do |type, name, sha1|
    [type, name, sha1_as_40_character_string(sha1)]
  end

  raise ">>> Invalid tree type '#{tree[0]}'" unless tree[0] == 'tree'
  raise ">>> Invalid size #{tree[1]} (expected #{tree[2].size})" unless tree[1] == tree[2].size
  raise ">>> Invalid SHA1 '#{Digest::SHA1.hexdigest(tree[3])}' (expected '#{tree_sha1}')" unless Digest::SHA1.hexdigest(tree[3]) == tree_sha1

  tree_data.each do |entry|
    case entry[0]
      when BLOB_MODE, EXECUTABLE_FILE_MODE then check_blob(entry[2])
      when TREE_MODE then check_tree(entry[2])
      else raise ">>> Unexpected object type '#{entry[0]}' for entry '#{entry.join(' ')}' of tree #{tree_sha1}"
    end
  end

  @trees_already_checked[tree_sha1] = true
end

def sha1_as_40_character_string(sha1)
  sha1.split('').map { |c| "%02x" % c.ord }.join
end

def check_blob(blob_sha1)
  puts "Checking blob #{blob_sha1}"

  @blobs_already_checked ||= {}

  if @blobs_already_checked[blob_sha1]
    puts "[blob already checked]"
    return
  end

  blob = read_git_object(blob_sha1)

  raise ">>> Invalid type '#{blob[0]}' (expected 'blob')" unless blob[0] == 'blob'
  raise ">>> Invalid size #{blob[1]} (expected #{blob[2].size})" unless blob[1] == blob[2].size
  raise ">>> Invalid SHA1 '#{Digest::SHA1.hexdigest(blob[3])}' (expected '#{blob_sha1}')" unless Digest::SHA1.hexdigest(blob[3]) == blob_sha1

  @blobs_already_checked[blob_sha1] = true
end

run! if __FILE__ == $0
