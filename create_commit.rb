require 'digest/sha1'
require 'zlib'
require 'fileutils'

def create_git_object(type, content)
  header       = "#{type} #{content.length}\0"
  store        = header + content
  sha1         = Digest::SHA1.hexdigest(store)    # 40-character string.
  zlib_content = Zlib::Deflate.deflate(store)
  path         = File.join('.git/objects/', sha1[0, 2], sha1[2, 38])

  FileUtils.mkpath File.dirname(path)
  File.write path, zlib_content

  sha1
end

# Note: one could use the Digest::SHA1.digest method over the original string to obtain the
# same results.
def sha1_as_20_byte_string(sha1)
  (1..20).map { |i| sha1[(i - 1) * 2, 2].to_i(16).chr }.join
end

####################
# Create 1st commit.
####################

blob1_sha1 = create_git_object(:blob, "what is up, doc?")
blob2_sha1 = create_git_object(:blob, "good to see you, marty!")

# http://stackoverflow.com/questions/14790681/format-of-git-tree-object
blob2_tree_sha1 = create_git_object(:tree, "100644 file1.txt\0" + sha1_as_20_byte_string(blob2_sha1))
blob1_tree_sha1 = create_git_object(
  :tree,
  [
    "40000 my_folder\0" + sha1_as_20_byte_string(blob2_tree_sha1),
    "100644 file2.txt\0" + sha1_as_20_byte_string(blob1_sha1)
  ].join
)

first_commit_sha1 = create_git_object(
  :commit,
  <<-END.gsub(/^ {4}/, '')
    tree #{blob1_tree_sha1}
    author Cassiano D'Andrea <cassiano.dandrea@tagview.com.br> #{Time.now.to_i} -0300
    committer Cassiano D'Andrea <cassiano.dandrea@tagview.com.br> #{Time.now.to_i} -0300

    1st commit using Ruby
  END
)

# Notice that '.git/HEAD' already points to 'refs/heads/master' by default. Remember: updating
# branch files directly is not recommended, given it DOES NOT update Git's reflog. This should
# be safer: "git update-ref refs/heads/master <sha1>"
File.write '.git/refs/heads/master', first_commit_sha1 + "\n"

####################
# Create 2nd commit.
####################

# This file hasn't changed! No need to regenerate its SHA1.
# blob1_sha1 = create_git_object(:blob, "what is up, doc?")

blob2_sha1 = create_git_object(:blob, "it's good to see you, marty!")

blob2_tree_sha1 = create_git_object(:tree, "100644 file1.txt\0" + sha1_as_20_byte_string(blob2_sha1))
blob1_tree_sha1 = create_git_object(
  :tree,
  [
    "40000 my_folder\0" + sha1_as_20_byte_string(blob2_tree_sha1),
    "100644 file2.txt\0" + sha1_as_20_byte_string(blob1_sha1)
  ].join
)

second_commit_sha1 = create_git_object(
  :commit,
  <<-END.gsub(/^ {4}/, '')
    tree #{blob1_tree_sha1}
    parent #{first_commit_sha1}
    author Cassiano D'Andrea <cassiano.dandrea@tagview.com.br> #{Time.now.to_i} -0300
    committer Cassiano D'Andrea <cassiano.dandrea@tagview.com.br> #{Time.now.to_i} -0300

    2nd commit using Ruby
  END
)

File.write '.git/refs/heads/master', second_commit_sha1 + "\n"
