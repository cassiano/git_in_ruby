# To make sure all objects are "loose":
#
# 1) Move all pack files to a temp folder
# 2) For each pack file (.pack extensions), run: git unpack-objects < <pack>

# List of possible exceptions.
class InvalidModeError          < StandardError; end
class InvalidSha1Error          < StandardError; end
class InvalidSizeError          < StandardError; end
class InvalidTypeError          < StandardError; end
class MissingObjectError        < StandardError; end
class ExcessiveCommitDataError  < StandardError; end
class MissingCommitDataError    < StandardError; end
class InvalidTreeData           < StandardError; end

# Required libraries.
require 'digest/sha1'
require 'active_record'

# Required external libraries.
Dir[File.join(File.dirname(File.expand_path(__FILE__)), 'lib', '*.rb')].each { |file| require file }

# Required models.
Dir[File.join(File.dirname(File.expand_path(__FILE__)), 'models', '*.rb')].each do |file|
  class_name = file[%r(.*/(.*)\.rb), 1]
  autoload class_name.camel_case, file
end

def run!(project_path, bare_repository)
  repository = FileSystemGitRepository.new(project_path: project_path, bare_repository: bare_repository)
  repository.head_fsck
end

run! ARGV[0] || '.', ARGV[1] && ARGV[1].downcase == 'bare' if __FILE__ == $0
