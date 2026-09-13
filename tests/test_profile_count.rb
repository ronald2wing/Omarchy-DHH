# Contract tests for bin/omarchy-fetch-profile-count: the streaming byte cap
# aborts a chunked (Content-Length-less) download, a stalled server is bounded by
# the read timeout, non-2xx and redirect limits fail closed, and the profile URL
# is HTTPS-only. Stdlib only; every network hop hits a loopback TCPServer, never
# an external host. Loading the script runs only its definitions — the __FILE__
# guard keeps main from executing.

require 'socket'

load File.expand_path('../bin/omarchy-fetch-profile-count', __dir__)

def assert(cond, msg)
  raise "FAIL: #{msg}" unless cond
end

# Reads a client's request line + headers so the server can respond once the
# request is complete.
def read_request(socket)
  request = +''
  request << socket.readpartial(65_536) until request.include?("\r\n\r\n")
  request
end

# 1. DHHFetch.capped_body raises the instant the cap is crossed (and returns
# the body under it).
class FakeResponse
  def initialize(chunks)
    @chunks = chunks
  end

  def read_body(&block)
    @chunks.each(&block)
  end
end

begin
  DHHFetch.capped_body(FakeResponse.new(['x' * 10, 'y' * 10]), max_bytes: 5)
  raise 'FAIL: capped_body did not raise on over-cap response'
rescue DHHFetch::BodyTooLarge
  # expected
end
assert(DHHFetch.capped_body(FakeResponse.new(%w[abc def]), max_bytes: 10) == 'abcdef',
       'capped_body returns the full body under the cap')

# 2. Streaming cap aborts mid-download: the server streams a 200 with no
# Content-Length, far more than the cap, and keeps the socket open. The cap must
# end the read long before the whole body could drain.
server = TCPServer.new('127.0.0.1', 0)
port = server.addr[1]
server_thread = Thread.new do
  socket = server.accept
  begin
    read_request(socket)
    socket.write("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n")
    10_000.times do
      socket.write('x' * 4096)
      sleep 0.02
    end
  rescue Errno::EPIPE, Errno::ECONNRESET, IOError
    # client aborted on the cap: expected
  ensure
    begin
      socket.close
    rescue StandardError
      nil
    end
    begin
      server.close
    rescue StandardError
      nil
    end
  end
end

t0 = Time.now
result = perform_request('127.0.0.1', port, use_ssl: false, open_timeout: 1,
                                            read_timeout: 1, max_bytes: 1024)
elapsed = Time.now - t0
assert(result.nil?, 'streaming cap aborts the download and returns nil')
assert(elapsed < 2, "cap aborts well before the body drains (#{elapsed.round(2)}s)")
server_thread.join

# 3. Read timeout: the server accepts and never responds.
server = TCPServer.new('127.0.0.1', 0)
port = server.addr[1]
server_thread = Thread.new do
  socket = server.accept
  begin
    read_request(socket)
    socket.read # block until the client gives up and closes
  rescue Errno::ECONNRESET, Errno::EPIPE, IOError
    # client closed on its read timeout: expected
  ensure
    begin
      socket.close
    rescue StandardError
      nil
    end
    begin
      server.close
    rescue StandardError
      nil
    end
  end
end

t0 = Time.now
result = perform_request('127.0.0.1', port, use_ssl: false, open_timeout: 0.5,
                                            read_timeout: 0.5, max_bytes: 1024)
elapsed = Time.now - t0
assert(result.nil?, 'read timeout returns nil')
assert(elapsed < 2, "read timeout aborts within ~2s (#{elapsed.round(2)}s)")
server_thread.join

# 4. Non-2xx (500) fails closed.
server = TCPServer.new('127.0.0.1', 0)
port = server.addr[1]
server_thread = Thread.new do
  socket = server.accept
  begin
    read_request(socket)
    socket.write("HTTP/1.1 500 Internal Server Error\r\nContent-Length: 5\r\n\r\nerror")
  ensure
    begin
      socket.close
    rescue StandardError
      nil
    end
    begin
      server.close
    rescue StandardError
      nil
    end
  end
end

result = perform_request('127.0.0.1', port, use_ssl: false, open_timeout: 1,
                                            read_timeout: 1, max_bytes: 1024)
assert(result.nil?, 'non-2xx (500) returns nil')
server_thread.join

# 5. Redirect limit: the server always answers 302. Its Location is plain http,
# so the HTTPS-only redirect rule rejects it on the first hop; the request count
# must stay bounded at or below DHHFetch::MAX_REDIRECTS + 1 either way.
requests = 0
mutex = Mutex.new
server = TCPServer.new('127.0.0.1', 0)
port = server.addr[1]
server_thread = Thread.new do
  (DHHFetch::MAX_REDIRECTS + 1).times do
    socket = server.accept
    mutex.synchronize { requests += 1 }
    begin
      read_request(socket)
      socket.write("HTTP/1.1 302 Found\r\nLocation: http://127.0.0.1:#{port}/\r\nContent-Length: 0\r\n\r\n")
    ensure
      begin
        socket.close
      rescue StandardError
        nil
      end
    end
  end
rescue IOError, Errno::EBADF
  # server closed once the client stopped following redirects
end

result = perform_request('127.0.0.1', port, use_ssl: false, open_timeout: 1,
                                            read_timeout: 1, max_bytes: 1024)
assert(result.nil?, 'redirect loop returns nil')
server.close
server_thread.join
count = mutex.synchronize { requests }
assert(count >= 1, 'made at least one request')
assert(count <= DHHFetch::MAX_REDIRECTS + 1, "redirect loop bounded: #{count} <= #{DHHFetch::MAX_REDIRECTS + 1}")

# 6. HTTPS-only: the profile URL is HTTPS and a plain http URL is rejected
# before any request is made.
assert(PROFILE_URL.is_a?(URI::HTTPS), 'PROFILE_URL is an HTTPS URI')
assert(fetch_profile_body(URI('http://127.0.0.1/')).nil?, 'http URL rejected without a request')

puts 'test_profile_count.rb: all assertions passed'
