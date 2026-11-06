# DHH::CLI: parse (values, switches, positionals, --help, the abort paths), usage_error and dataset_path.

require_relative 'test_helper'

USAGE = "usage: demo [--name N] [--write]\n"

def parse(argv, **kw)
  DHH::CLI.parse(argv, values: %w[name date], switches: %w[write verbose], usage: USAGE, **kw)
end

# [exit status, stdout, stderr] of parsing argv.
def outcome(argv, **kw) = capture { parse(argv, **kw) }

# Values and switches, as string keys; absent options are absent.
assert(parse([]) == {}, 'nothing given: empty hash')
assert(parse(%w[--name Ada --write]) == { 'name' => 'Ada', 'write' => true }, 'a value and a switch')
assert(parse(%w[--write --date 2020-01-01 --name Ada]) == { 'write' => true, 'date' => '2020-01-01', 'name' => 'Ada' }, 'order does not matter')
assert(parse(['--name', '-dash', '--name', '--- rule']) == { 'name' => '--- rule' }, 'a value may look like a dash; the last repeat wins')
assert(parse(%w[a --write b], positional: true) == { 'args' => %w[a b], 'write' => true }, 'positionals collected under args')
assert(parse([], positional: true) == { 'args' => [] }, 'no positionals: empty args')

# --help anywhere prints the usage and exits 0.
[%w[--help], %w[--name Ada --help], %w[--bogus --help]].each do |argv|
  status, out, = outcome(argv)
  assert(status.zero? && out == USAGE, "--help exits 0 with the usage: #{argv.inspect}")
end

# Failures abort with status 1, naming the problem and showing the usage.
[[%w[--name], 'missing value for --name'],
 [%w[--name --write], 'missing value for --name'],
 [%w[--date --name x], 'missing value for --date'],
 [%w[--bogus], 'unknown flag: --bogus'],
 [%w[stray], 'unexpected argument: stray'],
 [%w[--write stray], 'unexpected argument: stray']].each do |argv, message|
  status, _out, err = outcome(argv)
  assert(status == 1 && err.include?(message) && err.include?(USAGE), "#{argv.inspect} aborts: #{message}")
end
status, _out, err = outcome(%w[--bogus x], positional: true)
assert(status == 1 && err.include?('unknown flag: --bogus'), 'unknown flags abort even with positionals')

# usage_error and dataset_path.
status, _out, err = capture { DHH::CLI.usage_error('bad combination', USAGE) }
assert(status == 1 && err == "bad combination\n\n#{USAGE}", 'usage_error: the problem, a blank line and the usage')
assert(DHH::CLI.dataset_path({}, must_exist: true) == DHH::DATASET_PATH, 'dataset_path: the dataset by default')
assert(DHH::CLI.dataset_path({ 'file' => '/nonexistent/x.jsonl' }, must_exist: false) == '/nonexistent/x.jsonl', 'dataset_path: --file')
status, _out, err = capture { DHH::CLI.dataset_path({ 'file' => '/nonexistent/x.jsonl' }, must_exist: true) }
assert(status == 1 && err.include?('/nonexistent/x.jsonl does not exist'), 'dataset_path: a missing file aborts when it must exist')
assert(DHH::CLI::DEFAULT_DATASET == 'data/entries.jsonl', 'DEFAULT_DATASET is the dataset relative to the root')

puts 'test_cli.rb: all assertions passed'
