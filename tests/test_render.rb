# Contract tests for bin/omarchy-dhh-render's hardening: remote avatars are
# inlined (never a network URL), and a failed fetch falls back to the bundled
# default avatar.
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

# build_quote_html never references unavatar.io.
quote_html = build_quote_html({ 'text' => 'A short shareable quote' })
assert(!quote_html.include?('unavatar.io'), 'quote card has no unavatar.io URL')
