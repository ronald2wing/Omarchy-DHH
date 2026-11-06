# DHH::HTTP: the request builder, caps, timeouts, deadlines and redirects against loopback servers.

require_relative 'test_helper'

HTTP = DHH::HTTP
def loopback_uri(port, path = '/') = URI(loopback_url(port, path))

# The request builder.
request = HTTP.request('/a?b=1', accept: 'application/json')
assert(request.path == '/a?b=1' && request['User-Agent'] == HTTP::USER_AGENT && request['Accept'] == 'application/json',
       'request: the path, the User-Agent and the Accept header')
assert(HTTP.request('/', accept: nil)['Accept'] == '*/*', 'request: no Accept given leaves net/http\'s default')

# 1. The cap aborts mid-download.
port, thread = endless_body_server("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n")
t0 = Time.now
assert(HTTP.get(loopback_uri(port), max_body_bytes: 1024, timeout: 1).nil?, 'cap returns nil')
assert(Time.now - t0 < 2, 'cap aborts before the body drains')
thread.join

# 2. Read timeout, and a deadline shorter than the hop timeout clips the hop.
port, thread = stalling_server
t0 = Time.now
assert(HTTP.get(loopback_uri(port), max_body_bytes: 1024, timeout: 0.5).nil?, 'read timeout returns nil')
assert(Time.now - t0 < 2, 'read timeout aborts promptly')
thread.join
port, thread = stalling_server
t0 = Time.now
assert(HTTP.get(loopback_uri(port), max_body_bytes: 1024, timeout: 10, deadline: DHH::Deadline.after(0.5)).nil?, 'deadline returns nil')
assert(Time.now - t0 < 2, 'the deadline clips a longer hop timeout')
thread.join

# An expired deadline never opens a connection.
server, port, thread, connections = counting_server
assert(HTTP.get(loopback_uri(port), max_body_bytes: 1024, timeout: 1, deadline: DHH::Deadline.after(0)).nil?, 'expired deadline returns nil')
server.close
thread.join
assert(connections.call.zero?, 'no connection once the deadline has expired')

# 3. Success returns the body verbatim, with the Accept and User-Agent headers.
port, thread = one_shot_server do |socket, req|
  assert(req.include?('Accept: application/json'), 'the Accept header is sent')
  assert(req.include?("User-Agent: omarchy-dhh/#{DHH::VERSION}"), 'the User-Agent carries the manifest version')
  socket.write(http_response("{\"user\":{}}\n", type: 'application/json'))
end
assert(HTTP.get(loopback_uri(port), max_body_bytes: 1024, timeout: 1, accept: 'application/json') == "{\"user\":{}}\n", 'success returns the body')
thread.join

# 4. Non-2xx fails closed.
port, thread = status_server
assert(HTTP.get(loopback_uri(port), max_body_bytes: 1024, timeout: 1).nil?, '500 returns nil')
thread.join

# 5. A redirect loop is bounded and a plain-http target is never followed.
server, port, thread, requests = redirect_loop_server
assert(HTTP.get(loopback_uri(port), max_body_bytes: 1024, timeout: 1).nil?, 'redirect loop returns nil')
server.close
thread.join
assert(requests.call.between?(1, HTTP::MAX_REDIRECTS + 1), 'redirect count bounded')

# 6. Oversized redirect and error bodies fail closed under the cap.
{ '302 Found' => "Location: http://127.0.0.1:9/\r\n", '500 Internal Server Error' => '' }.each do |status, extra|
  port, thread = endless_body_server("HTTP/1.1 #{status}\r\n#{extra}\r\n")
  t0 = Time.now
  assert(HTTP.get(loopback_uri(port), max_body_bytes: 1024, timeout: 1).nil?, "#{status}: oversized body fails closed")
  assert(Time.now - t0 < 2, "#{status}: the cap aborts the drain")
  thread.join
end

# read_capped_body raises the instant the cap is crossed.
fake = Struct.new(:chunks) do
  def read_body(&block) = chunks.each(&block)
end
begin
  HTTP.read_capped_body(fake.new(['x' * 10, 'y' * 10]), max_body_bytes: 5)
  raise 'FAIL: read_capped_body did not raise'
rescue HTTP::BodyTooLarge
  # expected
end
assert(HTTP.read_capped_body(fake.new(%w[abc def]), max_body_bytes: 10) == 'abcdef', 'read_capped_body under the cap')

puts 'test_http.rb: all assertions passed'
