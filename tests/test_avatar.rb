# Contract tests for bin/omarchy-fetch-avatar: the streaming byte cap aborts a
# chunked (Content-Length-less) download, the batch byte budget stops the batch,
# timeouts and non-2xx fail closed, redirects never downgrade TLS, non-image
# mimes are forced to png, invalid handles never reach the wire, and the
# wall-clock deadline bounds the whole batch. Stdlib only; every network hop hits
# a loopback TCPServer, never an external host. Loading the script runs only its
# definitions — the __FILE__ guard keeps main from executing.

require 'socket'

load File.expand_path('../bin/omarchy-fetch-avatar', __dir__)

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

# Default loopback options: point fetch_one/fetch_avatar_batch at a plain-HTTP
# loopback server so no TLS server or 8s production deadline is ever involved.
# Per-case overrides (cap, timeouts, budget, deadline) are merged in.
def loopback(port, **extra)
  {
    host: '127.0.0.1',
    port: port,
    use_ssl: false,
    max_bytes: 1024,
    read_timeout: 1
  }.merge(extra)
end

# Starts a loopback server on an ephemeral port that handles one connection via
# the block (yielded [socket, request]), then closes both. Returns [port, thread].
def one_shot_server
  server = TCPServer.new('127.0.0.1', 0)
  port = server.addr[1]
  thread = Thread.new do
    socket = server.accept
    begin
      req = read_request(socket)
      yield socket, req
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
  [port, thread]
end

# Starts a loopback server that accepts connections until closed, handling each
# with the block (yielded [socket, request, port]). Returns [server, port, thread];
# the caller closes `server` to unblock the accept loop.
def accepting_server
  server = TCPServer.new('127.0.0.1', 0)
  port = server.addr[1]
  thread = Thread.new do
    loop do
      socket = server.accept
      begin
        req = read_request(socket)
        yield socket, req, port
      ensure
        begin
          socket.close
        rescue StandardError
          nil
        end
      end
    end
  rescue IOError, Errno::EBADF
    # server closed by the caller once the client stopped connecting
  end
  [server, port, thread]
end

# 1. Per-avatar cap aborts mid-download: the server streams a 200 with no
# Content-Length, far more than the cap, and keeps the socket open. The cap must
# end the read long before the whole body could drain, so a post-hoc size check
# could not pass.
port, thread = one_shot_server do |socket, _req|
  socket.write("HTTP/1.1 200 OK\r\nContent-Type: image/png\r\n\r\n")
  10_000.times do
    socket.write('x' * 4096)
    sleep 0.02
  end
rescue Errno::EPIPE, Errno::ECONNRESET, IOError
  # client aborted on the cap: expected
end

t0 = Time.now
result = fetch_one('big', **loopback(port))
elapsed = Time.now - t0
assert(result.nil?, 'per-avatar cap aborts the download and returns nil')
assert(elapsed < 2, "cap aborts well before the body drains (#{elapsed.round(2)}s)")
thread.join

# 2. Batch byte budget: each avatar fits under the per-avatar cap, but together
# they exceed max_total. The first is returned; the overflowing avatar is fetched
# (its size is unknowable before download) then discarded, and the batch stops.
connections = 0
mutex = Mutex.new
server, port, thread = accepting_server do |socket, req, _port|
  mutex.synchronize { connections += 1 }
  handle = req.split(' ')[1].split('/').last
  body = handle * 10 # 20 bytes per avatar
  socket.write("HTTP/1.1 200 OK\r\nContent-Type: image/png\r\nContent-Length: #{body.bytesize}\r\n\r\n#{body}")
end

result = fetch_avatar_batch(%w[aa bb], **loopback(port, max_total: 30))
assert(result.keys == ['aa'], 'only the first avatar is returned')
assert(!result.key?('bb'), 'the overflowing avatar is discarded')
server.close
thread.join
count = mutex.synchronize { connections }
assert(count == 2, "the overflowing avatar is fetched then discarded (#{count} connections)")

# 3. Read timeout: the server accepts and never responds.
port, thread = one_shot_server do |socket, _req|
  socket.read # block until the client gives up and closes
rescue Errno::ECONNRESET, Errno::EPIPE, IOError
  # client closed on its read timeout: expected
end

t0 = Time.now
result = fetch_one('stall', **loopback(port, read_timeout: 0.5))
elapsed = Time.now - t0
assert(result.nil?, 'read timeout returns nil')
assert(elapsed < 2, "read timeout aborts within ~2s (#{elapsed.round(2)}s)")
thread.join

# 4. Non-2xx (500) fails closed.
port, thread = one_shot_server do |socket, _req|
  socket.write("HTTP/1.1 500 Internal Server Error\r\nContent-Length: 5\r\n\r\nerror")
end

result = fetch_one('nope', **loopback(port))
assert(result.nil?, 'non-2xx (500) returns nil')
thread.join

# 5. Redirect policy: the server always answers 302 with a plain-http Location,
# which the HTTPS-only rule drops on the first hop (no TLS downgrade). The
# request count must stay bounded at or below DHHFetch::MAX_REDIRECTS + 1 either way.
requests = 0
mutex = Mutex.new
server, _port, thread = accepting_server do |socket, _req, port|
  mutex.synchronize { requests += 1 }
  socket.write("HTTP/1.1 302 Found\r\nLocation: http://127.0.0.1:#{port}/\r\nContent-Length: 0\r\n\r\n")
end

result = fetch_one('loop', **loopback(_port))
assert(result.nil?, 'plain-http redirect target is dropped and the handle omitted')
server.close
thread.join
count = mutex.synchronize { requests }
assert(count >= 1, 'made at least one request')
assert(count <= DHHFetch::MAX_REDIRECTS + 1, "redirect count bounded: #{count} <= #{DHHFetch::MAX_REDIRECTS + 1}")

# 6. Mime force: a non-image Content-Type is forced to image/png in the data URI.
port, thread = one_shot_server do |socket, _req|
  socket.write("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: 3\r\n\r\nabc")
end

result = fetch_one('mime', **loopback(port))
assert(result && result[:uri].start_with?('data:image/png;base64,'),
       'non-image Content-Type is forced to a png data URI')
thread.join

# 7. Handle validation: invalid handles are omitted without a single connection.
connections = 0
mutex = Mutex.new
server, port, thread = accepting_server do |_socket, _req, _port|
  mutex.synchronize { connections += 1 }
end

result = fetch_avatar_batch(['../etc', 'a b', '', 'x' * 16], **loopback(port))
assert(result == {}, 'all-invalid handle batch returns an empty hash')
server.close
thread.join
assert(mutex.synchronize { connections }.zero?, 'no connection opened for invalid handles')

# 8. Batch JSON contract + partial success: valid handles map to png data URIs,
# a failing handle is omitted.
server, port, thread = accepting_server do |socket, req, _port|
  handle = req.split(' ')[1].split('/').last
  if handle == 'bad'
    socket.write("HTTP/1.1 500 Internal Server Error\r\nContent-Length: 5\r\n\r\nerror")
  else
    socket.write("HTTP/1.1 200 OK\r\nContent-Type: image/png\r\nContent-Length: #{handle.bytesize}\r\n\r\n#{handle}")
  end
end

result = fetch_avatar_batch(%w[alice bob bad], **loopback(port))
assert(result.keys.sort == %w[alice bob], 'valid handles returned, failing handle omitted')
assert(result['alice'].start_with?('data:image/png;base64,'), 'alice is a png data URI')
assert(result['bob'].start_with?('data:image/png;base64,'), 'bob is a png data URI')
assert(!result.key?('bad'), '500 handle omitted from the result')
server.close
thread.join

# 9. Global deadline: a slow-trickling server would stream forever, but the
# injected total_deadline bounds the whole batch to well under 2s.
connections = 0
mutex = Mutex.new
server, port, thread = accepting_server do |socket, _req, _port|
  mutex.synchronize { connections += 1 }
  begin
    socket.write("HTTP/1.1 200 OK\r\nContent-Type: image/png\r\n\r\n")
    loop do
      socket.write('x' * 512)
      sleep 2
    end
  rescue Errno::EPIPE, Errno::ECONNRESET, IOError
    # client hit the deadline: expected
  end
end

t0 = Time.now
fetch_avatar_batch(%w[a b c d], **loopback(port, total_deadline: 1, read_timeout: 5,
                                            max_bytes: 1_000_000, max_total: 10_000_000))
elapsed = Time.now - t0
assert(elapsed < 2, "global deadline bounds the batch (#{elapsed.round(2)}s)")
server.close
thread.join
count = mutex.synchronize { connections }
assert(count < 4, "deadline stops the batch before all handles (#{count} < 4 connections)")

puts 'test_avatar.rb: all assertions passed'
