# Contract tests for bin/omarchy-dhh-render's hardening: remote avatars are
# inlined (never a network URL), a failed fetch falls back to the bundled
# default avatar, and run_captured kills and reaps a process group on deadline.
# Stdlib only; no network access. The render script's `__FILE__` guard keeps
# `main` (and the TERM trap) from running when the file is `load`ed here.

load File.expand_path('../bin/omarchy-dhh-render', __dir__)

def assert(cond, msg)
  raise "FAIL: #{msg}" unless cond
end

# Remote avatar inlined as a data URI: neither the reply quoted-card avatar nor
# the repost head avatar may leak a remote URL into the generated HTML.
fake = ->(_handle) { 'data:image/png;base64,AAAA' }

reply_entry = {
  'text' => 'Some reply body text',
  'date' => '2020-12-07',
  'kind' => 'reply',
  'context' => { 'author' => 'Someone Else', 'handle' => '@someone',
                 'text' => 'The original post', 'date' => '2020-12-06' }
}
repost_entry = {
  'text' => 'Some repost text',
  'date' => '2020-12-07',
  'kind' => 'repost',
  'context' => { 'author' => 'Someone Else', 'handle' => '@someone',
                 'text' => 'The original post', 'date' => '2020-12-06' }
}

reply_html = build_post_html(reply_entry, avatar_fetcher: fake)
assert(!reply_html.include?('unavatar.io'), 'reply avatar has no unavatar.io URL')
assert(!reply_html.include?('https://'), 'reply HTML has no remote https URL')
assert(reply_html.include?('data:image/'), 'reply avatar inlined as data URI')

repost_html = build_post_html(repost_entry, avatar_fetcher: fake)
assert(!repost_html.include?('unavatar.io'), 'repost avatar has no unavatar.io URL')
assert(!repost_html.include?('https://'), 'repost HTML has no remote https URL')
assert(repost_html.include?('data:image/'), 'repost avatar inlined as data URI')

# Failed fetch falls back to the bundled default avatar, still never remote.
fallback_html = build_post_html(reply_entry, avatar_fetcher: ->(_h) { nil })
assert(fallback_html.include?(DHHFetch.data_uri('image/png', File.binread(DEFAULT_AVATAR_PATH))),
       'nil avatar fetch falls back to the default avatar data URI')
assert(!fallback_html.include?('unavatar.io'), 'fallback HTML has no unavatar.io URL')

# run_captured: deadline exceeded -> whole group killed and reaped. The shell
# reports its own pid (its process-group id, since pgroup: true makes it the
# leader) on stdout, then execs a long sleep; the group must be gone afterward.
t0 = Time.now
stdout, _stderr, status, killed = run_captured(
  ['/bin/sh', '-c', 'echo $$; exec sleep 60'], deadline: 0.3, grace: 0.3
)
pid = stdout.strip.to_i
assert(pid > 0, 'captured the child pid from stdout')
assert(killed, 'run_captured reports killed on deadline')
assert(status.signaled?, 'run_captured status is signaled')
assert(Time.now - t0 < 3, 'run_captured returns under 3 seconds')
begin
  Process.kill(0, -pid)
  raise 'FAIL: process group still alive after kill'
rescue Errno::ESRCH
  # expected: the group is gone
end

# build_quote_html never references unavatar.io.
quote_html = build_quote_html({ 'text' => 'A short shareable quote' })
assert(!quote_html.include?('unavatar.io'), 'quote card has no unavatar.io URL')

# Real-magick trim regression: a synthetic 1200x2400 white PNG whose only
# non-white content is a black bar in the top 240px must trim down to that
# content, not stay at the full 2400px canvas (guards the inverted
# trim_to_content fallback). The bar is inset from the side edges — a bar
# spanning the full width degenerates magick's `%@` trim box. Skipped cleanly
# when magick is unavailable.
if File.executable?(MAGICK)
  Dir.mktmpdir('dhh-trim-test-') do |dir|
    raw = File.join(dir, 'raw.png')
    out = File.join(dir, 'out.png')
    built = system(MAGICK, '-size', '1200x2400', 'xc:white',
                   '-fill', 'black', '-draw', 'rectangle 16,0 583,239', raw,
                   out: File::NULL, err: File::NULL)
    assert(built, 'magick built the synthetic 1200x2400 test PNG')

    trim_to_content(raw, out)
    h = `#{MAGICK} identify -format %h #{out}`.strip.to_i
    assert(h == 240,
           "trim_to_content trimmed to the 240px content region, got #{h}px (full 2400 means the trim regression is back)")
  end
else
  puts 'test_render.rb: skipping trim_to_content regression test (magick unavailable)'
end

puts 'test_render.rb: all assertions passed'
