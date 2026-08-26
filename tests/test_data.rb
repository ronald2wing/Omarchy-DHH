# Structural validation of data/quotes.jsonl: every line must carry the keys its
# `type` schema requires, carry no unknown keys, and derive its `id` from the
# content (the JS<->Ruby drift guard). Stdlib only.

require 'json'
require_relative '../bin/dhh_helpers'

def assert(cond, msg)
  raise "FAIL: #{msg}" unless cond
end

# Per-type schema: every entry must carry the `required` keys and may carry the
# `optional` keys. `type` selects the registry entry. `post` entries that
# reference another post carry a `context` object plus a `kind` tag
# (`"reply"`, `"repost"`, or `"quote"`) whose optional `verified` must be a
# boolean when present and whose optional `verified_type` must be one of
# `individual`/`organization`/`government` (present only alongside
# `verified == true`); `link` keeps flat `title`/`domain` fields.
SCHEMA = {
  'post' => { required: %w[id text type source], optional: %w[date kind context] },
  'quote' => { required: %w[id text type source], optional: %w[date] },
  'link' => { required: %w[id text type source title domain], optional: %w[date] },
  'video' => { required: %w[id text type source], optional: %w[date] }
}.freeze

file = File.join(__dir__, '..', 'data', 'quotes.jsonl')
lines = File.read(file).split("\n").reject { |l| l.strip.empty? }

assert(lines.length >= 10, 'dataset has at least 10 entries')

seen = {}
lines.each do |line|
  o = JSON.parse(line)

  assert(o['type'].is_a?(String) && SCHEMA.key?(o['type']), "type is a known schema key: #{line.strip}")

  schema = SCHEMA[o['type']]
  schema[:required].each do |key|
    assert(o.key?(key), "required key present: #{key} in #{line.strip}")
  end
  o.keys.each do |key|
    assert(schema[:required].include?(key) || schema[:optional].include?(key), "unknown key: #{key} in #{line.strip}")
  end

  if o.key?('context')
    ctx = o['context']
    assert(ctx.is_a?(Hash), "context is a plain object: #{line.strip}")
    assert(ctx['author'].is_a?(String) && !ctx['author'].strip.empty?,
           "context.author is non-empty string: #{line.strip}")
    assert(ctx['handle'].is_a?(String) && !ctx['handle'].strip.empty?,
           "context.handle is non-empty string: #{line.strip}")
    if ctx.key?('text')
      assert(ctx['text'].is_a?(String) && !ctx['text'].strip.empty?,
             "context.text is non-empty string: #{line.strip}")
    end
    if ctx.key?('date')
      assert(ctx['date'].is_a?(String) && ctx['date'].match?(DHHHelpers::DATE_RE),
             "context.date format YYYY-MM-DD: #{line.strip}")
    end
    if ctx.key?('verified')
      assert([true, false].include?(ctx['verified']),
             "context.verified is boolean: #{line.strip}")
    end
    if ctx.key?('verified_type')
      assert(%w[individual organization government].include?(ctx['verified_type']),
             "context.verified_type is individual, organization, or government: #{line.strip}")
      assert(ctx['verified'] == true,
             "context.verified_type requires context.verified == true: #{line.strip}")
    end
    assert(o['kind'].is_a?(String) && %w[reply repost quote].include?(o['kind']),
           "kind present and valid when context present: #{line.strip}")
  else
    assert(!o.key?('kind'), "kind present only with context: #{line.strip}")
  end

  assert(o['text'].is_a?(String) && !o['text'].strip.empty?, "text is non-empty string: #{line.strip}")
  assert(o['id'].is_a?(String) && o['id'] == DHHHelpers.entry_id(o['text']),
         "id matches sha256(normalize(text)): #{line.strip}")
  assert(o['source'].is_a?(String) && !o['source'].strip.empty?, "source is non-empty string: #{line.strip}")
  assert(o['source'].start_with?('https://'), "source is https URL: #{line.strip}")
  if o.key?('date')
    assert(o['date'].is_a?(String) && o['date'].match?(DHHHelpers::DATE_RE),
           "date format YYYY-MM-DD: #{line.strip}")
  end
  assert(!seen.key?(o['source']), "duplicate source: #{o['source']}")
  seen[o['source']] = true
end

# Order invariant: date ascending, undated entries last, id tiebreak. Delegate
# to the sorter's own --check rather than reimplementing the comparator, so this
# validates both the dataset and the tool that maintains it.
sort_output = IO.popen(
  [File.join(__dir__, '..', 'bin', 'omarchy-sort-data'), '--check', '--file', file], &:read
)
assert($?.success?, "dataset is sorted (date, id): #{sort_output.strip}")

puts "test_data.rb: all assertions passed (#{lines.length} entries)"
