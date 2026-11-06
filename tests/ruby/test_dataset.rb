# The dataset (every line valid, unique sources, sorted), DHH::Dataset, and the dataset tools.

require 'open3'
require_relative 'test_helper'

Dataset = DHH::Dataset

# Every line validates against DHH::Dataset::SCHEMA; sources are unique and the
# file is sorted.
count = 0
seen = {}
Dataset.each_entry(DHH::DATASET_PATH) do |entry|
  count += 1
  errors = Dataset.validate(entry)
  assert(errors.empty?, "#{errors.join('; ')}: #{JSON.generate(entry)}")
  assert(!seen.key?(entry['source']), "duplicate source: #{entry['source']}")
  seen[entry['source']] = true
end
assert(count >= 10, 'dataset has at least 10 entries')
assert(Dataset.sorted?(DHH::DATASET_PATH), 'dataset is sorted by (date, id)')

# ---- id_for ----

assert(Dataset.id_for('Hello World') == 'b94d27b9', 'id_for known value')
assert(Dataset.id_for('Rails Doctrine') == 'c4639082', 'id_for known value 2')
assert(Dataset.id_for("  rails \t\n DOCTRINE ") == 'c4639082', 'id_for trims, lowercases and collapses whitespace first')

# ---- validate ----

good = { 'id' => Dataset.id_for('Hi'), 'type' => 'post', 'text' => 'Hi', 'source' => 'https://x.com/dhh/status/1' }
good_context = { 'author' => 'Jane', 'handle' => '@jane' }
assert(Dataset.validate(good).empty?, 'validate: a minimal post')
assert(Dataset.validate(good.merge('kind' => 'reply', 'context' => good_context)).empty?, 'validate: a reply')
{
  'a non-object' => [nil, 'entry is not an object'],
  'an unknown type' => [good.merge('type' => 'tweet'), 'type must be one of'],
  'a missing source' => [good.except('source'), 'missing source'],
  'an unknown key' => [good.merge('extra' => 1), 'extra is not allowed'],
  'a title on a post' => [good.merge('title' => 'T'), 'title is not allowed for type post'],
  'a blank text' => [good.merge('text' => ' '), 'text must be non-empty'],
  'a stale id' => [good.merge('id' => 'deadbeef'), 'derived from the text'],
  'an http source' => [good.merge('source' => 'http://x.com/1'), 'https'],
  'a bad date' => [good.merge('date' => '2020-1-1'), 'date must be YYYY-MM-DD'],
  'a kind without a context' => [good.merge('kind' => 'reply'), 'kind requires a context'],
  'a context without a kind' => [good.merge('context' => good_context), 'kind must be one of'],
  'a context on a quote' => [good.merge('type' => 'quote', 'kind' => 'reply', 'context' => good_context), 'context is not allowed'],
  'a handle without @' => [good.merge('kind' => 'reply', 'context' => good_context.merge('handle' => 'jane')), 'context.handle'],
  'a bare @' => [good.merge('kind' => 'reply', 'context' => good_context.merge('handle' => '@')), 'context.handle'],
  'a handle x.com does not allow' => [good.merge('kind' => 'reply', 'context' => good_context.merge('handle' => '@a b')), 'context.handle'],
  'a blank context text' => [good.merge('kind' => 'reply', 'context' => good_context.merge('text' => '')), 'context.text'],
  'an unknown context key' => [good.merge('kind' => 'reply', 'context' => good_context.merge('url' => 'x')), 'context.url'],
  'a verified_type without verified' => [good.merge('kind' => 'reply', 'context' => good_context.merge('verified_type' => 'individual')), 'requires context.verified'],
  'an unknown verified_type' => [good.merge('kind' => 'reply', 'context' => good_context.merge('verified' => true, 'verified_type' => 'gold')), 'context.verified_type must be one of'],
  'a link without a domain' => [good.merge('type' => 'link', 'title' => 'T'), 'missing domain']
}.each do |label, (entry, message)|
  assert(Dataset.validate(entry).any? { |e| e.include?(message) }, "validate rejects #{label} (#{Dataset.validate(entry).inspect})")
end

# ---- builders ----

built = Dataset.entry(type: 'post', text: 'Yes', source: 'https://x.com/dhh/status/2', date: '2020-01-02', kind: 'reply',
                context: Dataset.context(author: 'Jane', handle: '@jane', text: ' Original ', date: '', verified: true, verified_type: 'organization'))
assert(built == { 'id' => Dataset.id_for('Yes'), 'type' => 'post', 'text' => 'Yes', 'source' => 'https://x.com/dhh/status/2',
                  'date' => '2020-01-02', 'kind' => 'reply',
                  'context' => { 'author' => 'Jane', 'handle' => '@jane', 'text' => ' Original ', 'verified' => true, 'verified_type' => 'organization' } },
       'entry/context: dataset key order, blank keys dropped, id derived')
assert(built.keys == %w[id type text source date kind context], 'entry: the dataset key order')
link = Dataset.entry(type: 'link', text: 'L', source: 'https://example.com/a', title: 'A', domain: 'example.com', date: nil)
assert(link.keys == %w[id type text source title domain], 'entry: a link, no date')
assert(Dataset.context(author: 'A', handle: '@a', verified: false) == { 'author' => 'A', 'handle' => '@a' }, 'context: unverified stores no verified key')
[-> { Dataset.entry(type: 'post', text: 'x', source: 'https://x.com/1', title: 'T') },
 -> { Dataset.entry(type: 'quote', text: 'x', source: 'https://x.com/1', kind: 'reply', context: good_context) },
 -> { Dataset.entry(type: 'post', text: ' ', source: 'https://x.com/1') },
 -> { Dataset.context(author: 'A', handle: 'a') },
 -> { Dataset.context(author: 'A', handle: '@a', verified_type: 'individual') }].each_with_index do |build, index|
  build.call
  raise "FAIL: builder #{index} accepted an invalid entry"
rescue Dataset::InvalidEntry
  # expected
end
assert(Dataset.line(good) == "#{JSON.generate(good)}\n", 'line: one JSON line')

# ---- sort helpers on a scratch file ----

lines = [
  "{\"id\":\"bb\",\"text\":\"undated b\"}\n",
  "{\"id\":\"zz\",\"text\":\"late\",\"date\":\"2021-01-01\"}\n",
  "{\"id\":\"aa\",\"text\":\"undated a\"}\n",
  "{\"id\":\"ab\",\"text\":\"early 2\",\"date\":\"2020-01-01\"}\n",
  "{\"id\":\"aa\",\"text\":\"early 1\",  \"date\":\"2020-01-01\"}\n"
]
sorted = Dataset.sort_lines(lines)
assert(sorted == [lines[4], lines[3], lines[1], lines[2], lines[0]], 'sort_lines: date asc, id tiebreak, undated last by id')
assert(sorted.include?(lines[4]), 'sort_lines is byte-preserving (odd spacing survives)')
assert(Dataset.sort_lines(lines.dup.insert(2, "\n", "  \n")) == sorted, 'sort_lines skips blank lines, like each_entry')

Dir.mktmpdir('dhh-dataset-') do |dir|
  path = File.join(dir, 'q.jsonl')
  File.write(path, lines.join)
  assert(!Dataset.sorted?(path), 'sorted? false on an unsorted file')
  assert(Dataset.sort!(path) == true, 'sort! reports a change')
  assert(File.read(path) == sorted.join, 'sort! wrote the sorted lines')
  assert(Dataset.sort!(path) == false, 'sort! is idempotent')
  assert(Dir.children(dir) == ['q.jsonl'], 'sort! leaves no temp file behind')
  File.write(path, sorted.join + "\n")
  assert(Dataset.each_entry(path).count == 5 && !Dataset.sorted?(path), 'a blank line: each_entry skips it, the order check flags it')
  assert(Dataset.sort!(path) && File.read(path) == sorted.join, 'sort! drops the blank line')

  Dataset.append(path, [{ 'id' => 'a0', 'text' => 'earliest', 'date' => '2019-01-01' }])
  first = Dataset.each_entry(path).first
  assert(first['id'] == 'a0', 'append sorts, so the new earliest entry leads')
  assert(Dataset.each_entry(path).count == 6, 'append added one entry')

  # The CLI wrappers.
  sort_tool = File.join(ROOT, 'tools', 'sort-dataset')
  out, status = Open3.capture2(sort_tool, '--check', '--file', path)
  assert(status.success? && out.include?('is sorted'), 'sort-dataset --check on a sorted file')
  File.write(path, lines.join)
  out, status = Open3.capture2(sort_tool, '--file', path)
  assert(status.success? && out.include?('is not sorted') && File.read(path) == lines.join,
         'a bare sort-dataset reports without writing')
  _out, status = Open3.capture2(sort_tool, '--check', '--file', path)
  assert(status.exitstatus == 1, 'sort-dataset --check exits 1 on an unsorted file')
  _out, err, status = Open3.capture3(sort_tool, '--check', '--write', '--file', path)
  assert(status.exitstatus == 1 && err.include?('not both') && File.read(path) == lines.join, 'sort-dataset rejects --check with --write')
  out, status = Open3.capture2(sort_tool, '--write', '--file', path)
  assert(status.success? && out == "sorted #{path}\n" && File.read(path) == sorted.join, 'sort-dataset --write sorts the file')
  out, status = Open3.capture2(sort_tool, '--write', '--file', path)
  assert(status.success? && out == "#{path} already sorted\n", 'sort-dataset --write on a sorted file')

  add_tool = File.join(ROOT, 'tools', 'add-entry')
  out, status = Open3.capture2(add_tool, '--type', 'post', '--text', 'Hello World',
                               '--source', 'https://x.com/dhh/status/1', '--date', '2020-01-02')
  assert(status.success?, 'add-entry prints a line')
  entry = JSON.parse(out)
  assert(entry == { 'id' => 'b94d27b9', 'type' => 'post', 'text' => 'Hello World',
                    'source' => 'https://x.com/dhh/status/1', 'date' => '2020-01-02' }, 'add-entry line shape')
  out, status = Open3.capture2(add_tool, '--type', 'post', '--text', 'Yes', '--source', 'https://x.com/dhh/status/2',
                               '--kind', 'reply', '--context-author', 'Jane', '--context-handle', '@jane',
                               '--context-verified', '--context-verified-type', 'organization')
  assert(status.success? && JSON.parse(out)['context'] == { 'author' => 'Jane', 'handle' => '@jane', 'verified' => true, 'verified_type' => 'organization' },
         'add-entry builds a verified context')
  _out, err, status = Open3.capture3(add_tool, '--type', 'post', '--text', 'x', '--source', 'https://x.com/1', '--bogus')
  assert(status.exitstatus == 1 && err.include?('unknown flag: --bogus'), 'add-entry rejects unknown flags')
  _out, err, status = Open3.capture3(add_tool, '--type', 'post', '--text', 'x', '--source', 'http://x.com/1')
  assert(status.exitstatus == 1 && err.include?('https'), 'add-entry requires an https source')
  _out, err, status = Open3.capture3(add_tool, '--type', 'post', '--text', 'x', '--source', 'https://x.com/1',
                                     '--context-verified-type', 'individual', '--kind', 'reply',
                                     '--context-author', 'A', '--context-handle', '@a')
  assert(status.exitstatus == 1 && err.include?('requires context.verified'), 'add-entry gates verified_type on verified')
  _out, err, status = Open3.capture3(add_tool, '--type', 'post', '--text', 'x', '--source', 'https://x.com/1', '--title', 'T')
  assert(status.exitstatus == 1 && err.include?('title is not allowed for type post'), 'add-entry rejects --title on a non-link')
  _out, err, status = Open3.capture3(add_tool, '--type', 'post', '--text', '--write', '--source', 'https://x.com/1')
  assert(status.exitstatus == 1 && err.include?('missing value for --text'), 'add-entry never takes --write as the text')
  _out, err, status = Open3.capture3(add_tool, '--type', 'post', '--text', 'x', '--source', 'https://x.com/1', '--file', path)
  assert(status.exitstatus == 1 && err.include?('--file requires --write'), 'add-entry --file needs --write')
  _out, err, status = Open3.capture3(add_tool, '--type', 'post', '--text', 'appended', '--source', 'https://x.com/dhh/status/3',
                                     '--date', '2018-01-01', '--write', '--file', path)
  assert(status.success? && err.include?('appended 1 entry') && err.include?('(sorted)'), 'add-entry --write reports')
  assert(Dataset.each_entry(path).first['text'] == 'appended' && Dataset.sorted?(path), 'add-entry --write writes and sorts')
end

puts "test_dataset.rb: all assertions passed (#{count} entries)"
