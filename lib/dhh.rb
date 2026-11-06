# DHH root: ROOT, DATASET_PATH, VERSION, HANDLE and the require-time env scrub; loads every DHH module.

require 'json'

module DHH
  ROOT = File.expand_path('..', __dir__)
  DATASET_PATH = File.join(ROOT, 'data', 'entries.jsonl')
  # The one version string lives in manifest.json.
  VERSION = JSON.parse(File.read(File.join(ROOT, 'manifest.json'))).fetch('version')
  # DHH's x.com handle, bare: his profile, his statuses, his status URLs.
  HANDLE = 'dhh'

  module_function

  # Remove Ruby/Bundler env vars that could inject code or load paths into
  # later loads and any child process. The interpreter has already applied
  # them to *this* process, so the hardened shebang on each script is the real
  # control.
  def scrub_interpreter_env!
    %w[RUBYOPT RUBYLIB RUBYGEMS_GEMDEPS GEM_HOME GEM_PATH].each { |key| ENV.delete(key) }
    ENV.delete_if { |key, _| key.start_with?('BUNDLE_') }
  end
end

require_relative 'dhh/dataset'
require_relative 'dhh/deadline'
require_relative 'dhh/http'
require_relative 'dhh/untrusted_image'
require_relative 'dhh/avatars'
require_relative 'dhh/fxtwitter'
require_relative 'dhh/cli'

# A security control, run at require time on purpose: every helper and tool
# that loads this library gets a scrubbed environment, so the control cannot
# depend on each program remembering to call it. Keep this the last line.
DHH.scrub_interpreter_env!
