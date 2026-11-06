# helpers/fetch-post-count end to end against loopback servers.

require 'open3'
require_relative 'test_helper'
HELPER = File.join(ROOT, 'helpers', 'fetch-post-count')
load HELPER

FetchPostCount = DHH::FetchPostCount

# [exit status, stdout, stderr] of FetchPostCount.run against a server answering `body`.
def run_against(status_line, body)
  port, thread = one_shot_server do |socket, req|
    assert(req.include?('Accept: application/json'), 'fetch-post-count asks for JSON')
    socket.write(http_response(body, status: status_line, type: 'application/json'))
  end
  capture { FetchPostCount.run([], uri: URI(loopback_url(port, '/2/profile/dhh'))) }
ensure
  thread&.join
end

# Success: one integer line, exit 0.
status, out, = run_against('200 OK', '{"user":{"screen_name":"dhh","statuses":72434}}')
assert(status.zero? && out == "72434\n", "prints the post count (got #{status} #{out.inspect})")

# Failures: exit 1, nothing on stdout, a diagnostic on stderr.
[['200 OK', 'not json', 'malformed body'],
 ['200 OK', '{"user":{}}', 'missing statuses'],
 ['200 OK', '{"user":{"statuses":"72434"}}', 'string statuses'],
 ['200 OK', '{"user":{"statuses":72434.5}}', 'fractional statuses'],
 ['200 OK', '{"user":{"statuses":-1}}', 'negative statuses'],
 ['200 OK', '[1,2]', 'array body'],
 ['200 OK', 'null', 'null body'],
 ['500 Internal Server Error', 'error', 'server error']].each do |status_line, body, label|
  status, out, err = run_against(status_line, body)
  assert(status == 1 && out.empty? && !err.empty?, "#{label} exits 1")
end

# post_count on its own.
assert(FetchPostCount.post_count('{"user":{"statuses":0}}').zero?, 'post_count accepts zero')
assert(FetchPostCount.post_count('{"user":"dhh"}').nil? && FetchPostCount.post_count('').nil?, 'post_count: nil for odd shapes')

# The production URL.
uri = FetchPostCount::PROFILE_URI
assert(uri.is_a?(URI::HTTPS) && uri.to_s == 'https://api.fxtwitter.com/2/profile/dhh', 'the profile URL is HTTPS fxtwitter')

# CLI surface.
out, status = Open3.capture2(HELPER, '--help')
assert(status.success? && out.start_with?('usage: helpers/fetch-post-count'), 'fetch-post-count --help')
_out, err, status = Open3.capture3(HELPER, 'extra')
assert(status.exitstatus == 1 && err.include?('unexpected argument'), 'fetch-post-count rejects arguments')

puts 'test_fetch_post_count.rb: all assertions passed'
