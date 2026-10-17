# Unit tests for bin/omarchy-fetch-posts: walk_should_stop? decision logic,
# retry constants, reply_context fast path, __FILE__ guard. Stdlib only; no
# network.
#
# The script is loaded with `load`; its __FILE__ == $PROGRAM_NAME guard keeps
# the main HTTP loop from executing. Functions and constants at module level are
# available for isolated testing.
#
# Limitations:
#   - The retry loop and HTTP fetch are inline in the cursor walk and cannot be
#     tested end-to-end without faking ENDPOINT_HOST (TLS loopback + full profile
#     response shape). The constants and the walk_should_stop? helper are
#     verified instead.
#   - Argument parsing depends on ARGV, which is tested indirectly by verifying
#     --no-context appears in usage and --help exits 0.

load File.expand_path('../bin/omarchy-fetch-posts', __dir__)

def assert(cond, msg)
  raise "FAIL: #{msg}" unless cond
end

# 1. Retry constants exist with updated values.
assert(FETCH_RETRIES == 5, 'FETCH_RETRIES is 5 (headroom over max-observed 3-consecutive-404 run)')
assert(FETCH_RETRY_BACKOFF == 1.0, 'FETCH_RETRY_BACKOFF is 1.0')
assert(CONSECUTIVE_EMPTY_BREAK == 3, 'CONSECUTIVE_EMPTY_BREAK is 3')

# ---------------------------------------------------------------------------
# 2. walk_should_stop? — the pure decision predicate

# 2a. Stop when page limit reached.
assert(walk_should_stop?(pages_fetched: 3, pages_limit: 3, cursor: 'next',
                         results: ['a'], consecutive_empty: 0),
       'stop when pages_fetched >= pages_limit')

# 2b. Do not stop when under page limit.
assert(!walk_should_stop?(pages_fetched: 2, pages_limit: 3, cursor: 'next',
                          results: ['a'], consecutive_empty: 0),
       'continue when under page limit')

# 2c. Stop when cursor is nil.
assert(walk_should_stop?(pages_fetched: 1, pages_limit: 200, cursor: nil,
                         results: ['a'], consecutive_empty: 0),
       'stop when cursor is nil')

# 2d. Stop when cursor is empty string.
assert(walk_should_stop?(pages_fetched: 1, pages_limit: 200, cursor: '',
                         results: ['a'], consecutive_empty: 0),
       'stop when cursor is empty string')

# 2e. Do not stop on results with entries, regardless of consecutive_empty.
assert(!walk_should_stop?(pages_fetched: 1, pages_limit: 200, cursor: 'next',
                          results: ['a', 'b'], consecutive_empty: 0),
       'continue when results has entries (consecutive_empty=0)')
assert(!walk_should_stop?(pages_fetched: 1, pages_limit: 200, cursor: 'next',
                          results: ['a'], consecutive_empty: 2),
       'continue when results has entries even with consecutive_empty history')

# 2f. Do not stop on a single empty-results page (fluke mid-history).
assert(!walk_should_stop?(pages_fetched: 1, pages_limit: 200, cursor: 'next',
                          results: [], consecutive_empty: 1),
       'continue on first empty page (could be a fluke)')
assert(!walk_should_stop?(pages_fetched: 5, pages_limit: 200, cursor: 'next',
                          results: [], consecutive_empty: 2),
       'continue on second consecutive empty page')

# 2g. Stop when consecutive empty results hit the threshold.
assert(walk_should_stop?(pages_fetched: 100, pages_limit: 200, cursor: 'next',
                         results: [], consecutive_empty: 3),
       'stop when results empty and consecutive_empty >= CONSECUTIVE_EMPTY_BREAK')
assert(walk_should_stop?(pages_fetched: 1, pages_limit: 200, cursor: 'next',
                         results: [], consecutive_empty: 5),
       'stop when consecutive_empty exceeds threshold')

# 2h. Regression guard: page that adds NO new entries but HAS results must NOT stop.
# This is the bug that broke --pages N on page 1: results non-empty, page_new=0,
# but the walk must continue.
assert(!walk_should_stop?(pages_fetched: 1, pages_limit: 3, cursor: 'page2token',
                          results: ['fully-known-post'], consecutive_empty: 0),
       'DO NOT stop when results non-empty but page adds nothing new')

# ---------------------------------------------------------------------------
# 3. reply_context with skip_reply_fetch: true returns bare context without making a fetch.
result = { 'replying_to' => { 'screen_name' => 'someuser', 'status' => '12345' } }
resolved = {}
ctx = reply_context(nil, result, resolved, skip_reply_fetch: true)
assert(ctx.is_a?(Hash), 'reply_context returns a Hash when skip_reply_fetch: true')
assert(ctx['author'] == 'someuser', 'bare author is the screen name')
assert(ctx['handle'] == '@someuser', 'bare handle is @screen_name')
assert(resolved.empty?, 'fast path does not populate resolved_replies cache')

# 4. reply_context without skip_reply_fetch: makes a real fetch (will fail with nil http),
#    falls back to bare context.
result2 = { 'replying_to' => { 'screen_name' => 'otheruser', 'status' => '99' } }
resolved2 = {}
ctx2 = reply_context(nil, result2, resolved2, skip_reply_fetch: false)
assert(ctx2.is_a?(Hash), 'reply_context returns a Hash on fetch failure')
assert(ctx2['author'] == 'otheruser', 'falls back to bare author on fetch failure')
assert(ctx2['handle'] == '@otheruser', 'falls back to bare handle on fetch failure')
assert(resolved2.key?('99'), 'failed fetch is cached under its status id')
assert(resolved2['99'] == ctx2, 'cached value matches returned context')

# 5. reply_context with nil/empty target_id returns bare immediately.
result3 = { 'replying_to' => { 'screen_name' => 'noid', 'status' => nil } }
resolved3 = {}
ctx3 = reply_context(nil, result3, resolved3, skip_reply_fetch: false)
assert(ctx3['author'] == 'noid', 'nil target_id returns bare')
assert(ctx3['handle'] == '@noid', 'nil target_id returns bare')

# 6. reply_context with replying_to string (legacy format) and skip_reply_fetch: true.
result4 = { 'replying_to' => 'legacyuser', 'replying_to_status' => '42' }
resolved4 = {}
ctx4 = reply_context(nil, result4, resolved4, skip_reply_fetch: true)
assert(ctx4['author'] == 'legacyuser', 'legacy format fast path returns bare')
assert(ctx4['handle'] == '@legacyuser', 'legacy format fast path returns bare')
assert(resolved4.empty?, 'fast path does not cache in legacy format')

# 7. reply_context with skip_reply_fetch: true and target_id is empty in legacy format.
result5 = { 'replying_to' => 'legacy2', 'replying_to_status' => '' }
resolved5 = {}
ctx5 = reply_context(nil, result5, resolved5, skip_reply_fetch: false)
assert(ctx5['author'] == 'legacy2', 'empty target_id returns bare immediately')
assert(ctx5['handle'] == '@legacy2', 'empty target_id is bare')

# 8. Verified context stamping does not blow up on nil author.
assert(author_verified?(nil) == false, 'author_verified? returns false for nil')
assert(author_verified?({}) == false, 'author_verified? returns false for empty hash')

ctx6 = {}
stamp_verification(ctx6, { 'verification' => { 'verified' => true, 'type' => 'individual' } })
assert(ctx6['verified'] == true, 'stamp_verification sets verified')
assert(ctx6['verified_type'] == 'individual', 'stamp_verification sets verified_type')

ctx7 = {}
stamp_verification(ctx7, { 'verification' => { 'verified' => false } })
assert(!ctx7.key?('verified'), 'stamp_verification omits verified for unverified author')

# 9. utc_date serializes correctly.
assert(utc_date(0) == '1970-01-01', 'utc_date(0) is epoch')

puts 'test_fetch_posts.rb: all assertions passed'