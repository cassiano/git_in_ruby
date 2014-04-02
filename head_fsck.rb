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

# Require standard libraries.
require 'digest/sha1'
require 'zlib'
require 'fileutils'
# require 'debug'

# Require external libraries.
Dir[File.join(File.dirname(File.expand_path(__FILE__)), "lib", "*.rb")].each { |file| require file }

# Require models.
require File.join(File.dirname(File.expand_path(__FILE__)), 'models', 'git_repository')
require File.join(File.dirname(File.expand_path(__FILE__)), 'models', 'git_object')
require File.join(File.dirname(File.expand_path(__FILE__)), 'models', 'blob')
Dir[File.join(File.dirname(File.expand_path(__FILE__)), "models", "*.rb")].each { |file| require file }

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
