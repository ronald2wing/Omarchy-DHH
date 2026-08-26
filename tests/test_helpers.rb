# Contract tests for bin/dhh_helpers.rb, the Ruby port of format.js/search.js.
# Mirrors the relevant assertions from tests/test_format.js and pins the
# JS<->Ruby parity values. Stdlib only.
#
# Note the quirk this pins down: hash32 is the JS double-rounded FNV-1a (JS
# multiplies with IEEE-754 doubles), NOT canonical FNV-1a — "abc" hashes to
# 440920332 here instead of the canonical 440920331.

require_relative '../bin/dhh_helpers'

def assert(cond, msg)
  raise "FAIL: #{msg}" unless cond
end

# escape_html: escapes &, <, >, and both quote characters, & applied first so
# the literals it introduces are not themselves re-escaped.
assert(DHHHelpers.escape_html("<>&\"'") == '&lt;&gt;&amp;&quot;&#39;', 'escape_html escapes &<> and quotes')
assert(DHHHelpers.escape_html('plain text 123') == 'plain text 123', 'escape_html plain text unchanged')
assert(DHHHelpers.escape_html('&amp;') == '&amp;amp;', 'escape_html & applied first, result not re-escaped')

# format_date: fixed prior year
assert(DHHHelpers.format_date('2020-12-07') == 'Dec 7, 2020', 'format_date prior year')

# format_date: empty / garbage
assert(DHHHelpers.format_date('') == '', 'format_date empty string')
assert(DHHHelpers.format_date(nil) == '', 'format_date nil')
assert(DHHHelpers.format_date('not a date') == '', 'format_date garbage')
assert(DHHHelpers.format_date('2020-13-45') == '', 'format_date invalid month')

# format_engagement_count: drops the decimal at/above 10 of a unit (values match the JS
# Number-to-String semantics in format.js).
{
  999 => '999', 1000 => '1K', 1023 => '1K', 1555 => '1.6K', 9999 => '10K',
  10_000 => '10K', 12_345 => '12K', 999_999 => '1000K', 1_000_000 => '1M',
  1_500_000 => '1.5M'
}.each do |n, expected|
  assert(DHHHelpers.format_engagement_count(n) == expected, "format_engagement_count boundary #{n}")
end

# decorative_engagement_counts: deterministic, four integer values in X-plausible ranges.
t = 'determinism probe'
c1 = DHHHelpers.decorative_engagement_counts(t)
c2 = DHHHelpers.decorative_engagement_counts(t)
assert(c1 == c2, 'decorative_engagement_counts deterministic')
assert(c1.keys.sort == %i[like reply repost views], 'decorative_engagement_counts four keys')
assert(c1.values.all? { |v| v.is_a?(Integer) }, 'decorative_engagement_counts integer values')
assert(c1[:reply].between?(50, 900), 'decorative_engagement_counts reply in range')
assert(c1[:repost].between?(500, 3000), 'decorative_engagement_counts repost in range')
assert(c1[:like].between?(2000, 80_000), 'decorative_engagement_counts like in range')
assert(c1[:views].between?(100_000, 3_000_000), 'decorative_engagement_counts views in range')

# decorative_engagement_counts: empty text still yields a valid hash-based set.
c0 = DHHHelpers.decorative_engagement_counts('')
assert(c0[:reply].is_a?(Integer) && c0[:reply].between?(50, 900), 'decorative_engagement_counts empty text')

# hash32: deterministic 32-bit unsigned integer (JS double-rounded FNV-1a).
assert(DHHHelpers.hash32('abc') == DHHHelpers.hash32('abc'), 'hash32 deterministic')
assert(DHHHelpers.hash32('') == 2_166_136_261, 'hash32 empty = FNV offset basis')
assert(DHHHelpers.hash32('abc') == 440_920_332, 'hash32 known value abc (JS double-rounded, not canonical FNV)')
assert(DHHHelpers.hash32('a') == 3_826_002_220, "hash32 known value 'a'")
assert(DHHHelpers.hash32('abc').between?(0, 4_294_967_295), 'hash32 32-bit unsigned')

# slugify / normalize / entry_id parity.
assert(DHHHelpers.slugify('Meetings are toxic!') == 'meetings-are-toxic', 'slugify basic')
assert(DHHHelpers.slugify('  --  ') == '', 'slugify empty')
assert(DHHHelpers.slugify('Rails Doctrine! 2024') == 'rails-doctrine-2024', 'slugify punctuation/space')
assert(DHHHelpers.normalize('  Hello   WORLD  ') == 'hello world', 'normalize collapses case/whitespace')
assert(DHHHelpers.normalize("  RAILS   Doctrine\t") == 'rails doctrine', 'normalize tab collapse')
assert(DHHHelpers.entry_id('Hello World') == 'b94d27b9', 'entry_id known value')
assert(DHHHelpers.entry_id('Rails Doctrine') == 'c4639082', 'entry_id known value 2')

# strip_leading_mentions: mirrors search.js's stripLeadingMentions; strips every
# leading "@word<space>" run, leaves a bare trailing handle unchanged, and treats
# an empty text or handle as a no-op.
assert(DHHHelpers.strip_leading_mentions('@foo hi', '@foo') == 'hi', 'strip_leading_mentions single mention')
assert(DHHHelpers.strip_leading_mentions('@foo @bar hi', '@foo') == 'hi', 'strip_leading_mentions chained mentions')
assert(DHHHelpers.strip_leading_mentions('@foo', '@foo') == '@foo', 'strip_leading_mentions bare handle unchanged')
assert(DHHHelpers.strip_leading_mentions('no mention', '@foo') == 'no mention', 'strip_leading_mentions no mention')
assert(DHHHelpers.strip_leading_mentions('anything', '') == 'anything', 'strip_leading_mentions empty handle no-op')
assert(DHHHelpers.strip_leading_mentions('', '@foo') == '', 'strip_leading_mentions empty text no-op')

# Divergence from search.js (which coerces via String(text || "")): the Ruby guard
# calls String#empty? directly, so a non-string text raises rather than coercing.
begin
  DHHHelpers.strip_leading_mentions(123, '@foo')
  raise 'strip_leading_mentions expected NoMethodError for non-string text'
rescue NoMethodError
  # expected: no coercion in the Ruby port.
end

puts 'test_helpers.rb: all assertions passed'
