# tools/import-posts: walk, contexts, dedupe before fetch, invalid statuses, --file --write, against loopback servers.

require 'open3'
require_relative 'test_helper'
load File.join(ROOT, 'tools', 'import-posts')

ImportPosts = DHH::ImportPosts

# last_page?
last = ->(**kw) { ImportPosts.last_page?(**{ pages_fetched: 1, max_pages: 200, cursor: 'next', empty_pages: 0 }.merge(kw)) }
assert(last.call(pages_fetched: 3, max_pages: 3), 'stop at the page limit')
assert(!last.call(pages_fetched: 2, max_pages: 3), 'continue under the page limit')
assert(last.call(cursor: nil) && last.call(cursor: ''), 'stop when the cursor is exhausted')
assert(!last.call(empty_pages: 0), 'continue while results arrive (a page with results resets the run)')
assert(!last.call(empty_pages: 1) && !last.call(empty_pages: 2), 'a lone empty page may be a fluke')
assert(last.call(empty_pages: ImportPosts::TAIL_EMPTY_PAGES) && last.call(empty_pages: 5), 'stop at the tail threshold')

# context_from, with the author's verification.
author = { 'name' => 'Jane Doe', 'screen_name' => 'janedoe', 'verification' => { 'verified' => true, 'type' => 'organization' } }
built = ImportPosts.context_from(author, { 'text' => ' Original ', 'created_timestamp' => 86_400 })
assert(built == { 'author' => 'Jane Doe', 'handle' => '@janedoe', 'text' => ' Original ', 'date' => '1970-01-02',
                  'verified' => true, 'verified_type' => 'organization' }, 'context_from: full shape')
assert(ImportPosts.context_from(author, { 'text' => '  ', 'created_timestamp' => 0 }).keys == %w[author handle verified verified_type],
       'context_from omits a blank text and a zero timestamp')
assert(ImportPosts.context_from({ 'name' => 'A', 'screen_name' => 'a' }) == { 'author' => 'A', 'handle' => '@a' }, 'context_from: bare')
weird = author.merge('verification' => { 'verified' => true, 'type' => 'weird' })
assert(ImportPosts.context_from(weird).slice('verified', 'verified_type') == { 'verified' => true }, 'an unknown badge variant is left out')
[{ 'verified' => false, 'type' => 'individual' }, 'yes', nil].each do |verification|
  context = ImportPosts.context_from(author.merge('verification' => verification))
  assert(!context.key?('verified') && !context.key?('verified_type'), "no verification stored for #{verification.inspect}")
end
[{ 'name' => '', 'screen_name' => 'a' }, { 'name' => 'A', 'screen_name' => nil }].each do |invalid|
  ImportPosts.context_from(invalid)
  raise "FAIL: context_from accepted #{invalid.inspect}"
rescue DHH::Dataset::InvalidEntry
  # expected: the builder validates
end

# reply_context paths (http is nil, so any real fetch fails and falls back).
resolved = {}
ctx = ImportPosts.reply_context(nil, { 'replying_to' => { 'screen_name' => 'someuser', 'status' => '12345' } }, resolved, bare_replies: true)
assert(ctx == { 'author' => 'someuser', 'handle' => '@someuser' } && resolved.empty?, 'bare replies: bare context, uncached')
resolved = {}
ctx = ImportPosts.reply_context(nil, { 'replying_to' => { 'screen_name' => 'other', 'status' => '99' } }, resolved)
assert(ctx == { 'author' => 'other', 'handle' => '@other' } && resolved['99'] == ctx, 'failed fetch falls back to bare and caches')
assert(ImportPosts.reply_context(nil, { 'replying_to' => { 'screen_name' => 'noid', 'status' => nil } }, {})['handle'] == '@noid', 'nil parent id is bare')
assert(ImportPosts.reply_context(nil, { 'replying_to' => 'legacy', 'replying_to_status' => '42' }, {}, bare_replies: true)['handle'] == '@legacy',
       'legacy string replying_to')
assert(ImportPosts.reply_context(nil, { 'replying_to' => 'legacy2', 'replying_to_status' => '' }, {})['handle'] == '@legacy2', 'empty legacy parent id')

assert(ImportPosts.utc_date(0) == '1970-01-01', 'utc_date epoch')

# ---- end to end against a loopback fxtwitter ----

DHH_AUTHOR = { 'name' => 'DHH', 'screen_name' => 'dhh' }.freeze

def status(id, text, extra = {})
  { 'id' => id, 'text' => text, 'created_timestamp' => 1_600_000_000 + id.to_i, 'author' => DHH_AUTHOR }.merge(extra)
end

def respond_json(socket, value)
  socket.write(http_response(JSON.generate(value), type: 'application/json', headers: { 'Connection' => 'close' }))
end

# Run the tool in-process against a loopback server that answers every
# statuses request with `page` and every single-status request with a parent
# post. Returns [stdout, stderr, requested paths].
def import_against(page, argv)
  paths = []
  server, port, thread, = counting_server do |socket, req, _p|
    path = req[/\AGET (\S+)/, 1]
    paths << path
    if path.include?('/statuses?')
      respond_json(socket, page)
    else
      respond_json(socket, { 'code' => 200, 'tweet' => { 'text' => 'Parent post', 'created_timestamp' => 1_500_000_000,
                                                        'author' => { 'name' => 'Pat', 'screen_name' => 'pat' } } })
    end
  end
  _status, out, err = capture { ImportPosts.run(argv, base_uri: URI(loopback_url(port, ''))) }
  [out, err, paths]
ensure
  server&.close
  thread&.join(2)
end

Dir.mktmpdir('dhh-import-') do |dir|
  dataset = File.join(dir, 'entries.jsonl')
  known_reply = status('100', '@pat A reply that is already in the dataset', 'replying_to' => { 'screen_name' => 'pat', 'status' => '7' })
  known_line = DHH::Dataset.line(DHH::Dataset.entry(type: 'post', text: known_reply['text'], source: 'https://x.com/dhh/status/100',
                                                    date: '2020-09-13', kind: 'reply',
                                                    context: DHH::Dataset.context(author: 'pat', handle: '@pat')))
  File.write(dataset, known_line)

  # Dedupe before fetch: a reply already in the dataset costs no parent fetch.
  # A status that would not validate (a repost of a nameless author) is
  # skipped with a warning.
  nameless_repost = status('104', 'Reposted words', 'author' => { 'name' => '', 'screen_name' => 'anon' },
                                                    'reposted_by' => { 'screen_name' => 'dhh' })
  page = { 'results' => [known_reply, status('101', 'Someone else', 'author' => { 'name' => 'X', 'screen_name' => 'x' }), nameless_repost],
           'cursor' => { 'bottom' => nil } }
  out, err, paths = import_against(page, ['--file', dataset])
  assert(paths.length == 1 && paths.first.start_with?('/2/profile/dhh/statuses?count=100'), "a known reply is skipped before its parent fetch (#{paths.inspect})")
  assert(out.empty? && err.include?('0 new (dry run)'), 'nothing new from known, foreign and invalid statuses')
  assert(err.include?('skipping https://x.com/dhh/status/104: context.author must be non-empty'), "an invalid status is skipped with a warning (#{err.inspect})")

  # A new reply fetches its parent once; the dry run prints oldest first and
  # leaves the file alone.
  page = { 'results' => [status('103', 'Newest standalone'),
                         status('102', '@pat A new reply', 'replying_to' => { 'screen_name' => 'pat', 'status' => '8' }),
                         known_reply],
           'cursor' => { 'bottom' => '' } }
  out, err, paths = import_against(page, ['--file', dataset])
  assert(paths.length == 2 && paths.last == '/dhh/status/8', "one parent fetch for the new reply (#{paths.inspect})")
  lines = out.lines.map { |line| JSON.parse(line) }
  assert(lines.map { |e| e['source'] } == %w[https://x.com/dhh/status/102 https://x.com/dhh/status/103], 'dry run prints oldest first')
  assert(lines.first['context'] == { 'author' => 'Pat', 'handle' => '@pat', 'text' => 'Parent post', 'date' => '2017-07-14' },
         'the reply context comes from the fetched parent')
  assert(lines.all? { |e| DHH::Dataset.validate(e).empty? }, 'imported entries validate')
  assert(err.include?('2 new (dry run) [1 standalone, 1 reply]'), "dry-run summary (#{err.inspect})")
  assert(File.read(dataset) == known_line, 'a dry run leaves the dataset untouched')

  # --bare-replies skips the parent fetch.
  _out, _err, paths = import_against(page, ['--file', dataset, '--bare-replies'])
  assert(paths.length == 1, '--bare-replies makes no parent fetch')

  # --file --write appends to the scratch dataset, keeps it sorted and
  # prints the number of new entries.
  out, err, = import_against(page, ['--file', dataset, '--write'])
  assert(out == "2\n" && err.include?('(appended, sorted)'), "--write prints the new count (#{out.inspect}, #{err.inspect})")
  sources = DHH::Dataset.each_entry(dataset).map { |e| e['source'] }.sort
  assert(sources == %w[https://x.com/dhh/status/100 https://x.com/dhh/status/102 https://x.com/dhh/status/103], '--write appended both')
  assert(DHH::Dataset.sorted?(dataset), '--write keeps the dataset sorted')
  out, err, = import_against(page, ['--file', dataset, '--write'])
  assert(out == "0\n" && err.include?('nothing appended'), 'a second --write finds nothing new')
end

# CLI surface.
tool = File.join(ROOT, 'tools', 'import-posts')
out, status = Open3.capture2(tool, '--help')
assert(status.success? && out.start_with?('usage: tools/import-posts') && out.include?('--bare-replies'), 'import-posts --help')
_out, err, status = Open3.capture3(tool, '--pages', 'x')
assert(status.exitstatus == 1 && err.include?('--pages must be an integer'), 'import-posts validates --pages')
_out, err, status = Open3.capture3(tool, '--limit', '5')
assert(status.exitstatus == 1 && err.include?('unknown flag: --limit'), 'import-posts has no --limit')
_out, err, status = Open3.capture3(tool, '--nope')
assert(status.exitstatus == 1 && err.include?('unknown flag: --nope'), 'import-posts rejects unknown flags')

puts 'test_import_posts.rb: all assertions passed'
