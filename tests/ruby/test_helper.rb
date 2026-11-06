# Shared by the Ruby tests: the library, assert, the scrub check, output capture, loopback servers and image fixtures.

require 'socket'
require 'stringio'
require 'zlib'
require 'tmpdir'

# Interpreter variables set before lib/dhh loads must be gone after it: the
# scrub runs at require time, so no helper or tool can forget it. Both values are
# inert in this already-running interpreter.
ENV['RUBYOPT'] = '-W0'
ENV['BUNDLE_DHH_SCRUB_CHECK'] = '1'
require_relative '../../lib/dhh'

ROOT = DHH::ROOT

def assert(cond, msg)
  raise "FAIL: #{msg}" unless cond
end

assert(!ENV.key?('RUBYOPT') && !ENV.key?('BUNDLE_DHH_SCRUB_CHECK'), 'requiring lib/dhh scrubs the interpreter environment')

# Run the block with $stdout and $stderr captured. Returns [exit status,
# stdout, stderr]; the status is 0 when the block returns without exiting.
def capture
  out = StringIO.new
  err = StringIO.new
  saved = [$stdout, $stderr]
  $stdout = out
  $stderr = err
  status = 0
  begin
    yield
  rescue SystemExit => e
    status = e.status
  ensure
    $stdout, $stderr = saved
  end
  [status, out.string, err.string]
end

# One HTTP/1.1 response with a Content-Length, for the loopback servers.
def http_response(body, status: '200 OK', type: nil, headers: {})
  head = ["HTTP/1.1 #{status}"]
  head << "Content-Type: #{type}" if type
  headers.each { |name, value| head << "#{name}: #{value}" }
  head << "Content-Length: #{body.bytesize}"
  "#{head.join("\r\n")}\r\n\r\n#{body}"
end

# Read a client's request line + headers so the server can answer once the
# request is complete.
def read_request(socket)
  request = +''
  request << socket.readpartial(65_536) until request.include?("\r\n\r\n")
  request
end

# A loopback server on an ephemeral port that handles one connection via the
# block (socket, request), then closes. Returns [port, thread].
def one_shot_server
  server = TCPServer.new('127.0.0.1', 0)
  port = server.addr[1]
  thread = Thread.new do
    socket = server.accept
    begin
      yield socket, read_request(socket)
    ensure
      socket.close rescue nil
      server.close rescue nil
    end
  end
  [port, thread]
end

# A loopback server that accepts until closed, handling each connection via
# the block (socket, request, port). Returns [server, port, thread]; close
# `server` to end the loop.
def accepting_server
  server = TCPServer.new('127.0.0.1', 0)
  port = server.addr[1]
  thread = Thread.new do
    loop do
      socket = server.accept
      begin
        yield socket, read_request(socket), port
      ensure
        socket.close rescue nil
      end
    end
  rescue IOError, Errno::EBADF
    # closed by the caller
  end
  [server, port, thread]
end

# A server that streams an endless body after `head`, for the cap tests.
def endless_body_server(head)
  one_shot_server do |socket, _req|
    socket.write(head)
    10_000.times do
      socket.write('x' * 4096)
      sleep 0.02
    end
  rescue Errno::EPIPE, Errno::ECONNRESET, IOError
    # client aborted on its cap: expected
  end
end

# A server that reads the request and never answers, for the read timeouts.
def stalling_server
  one_shot_server do |socket, _req|
    socket.read
  rescue Errno::ECONNRESET, Errno::EPIPE, IOError
    # client gave up on its timeout: expected
  end
end

# A server that answers one request with `status` and a short body, for the
# non-2xx paths.
def status_server(status = '500 Internal Server Error', body = 'error')
  one_shot_server { |socket, _req| socket.write(http_response(body, status: status)) }
end

# An accepting server that counts its connections. Returns
# [server, port, thread, count] where count.call reads the tally; close
# `server` to end the loop.
def counting_server
  connections = 0
  mutex = Mutex.new
  server, port, thread = accepting_server do |socket, req, p|
    mutex.synchronize { connections += 1 }
    yield socket, req, p if block_given?
  end
  [server, port, thread, -> { mutex.synchronize { connections } }]
end

# A counting server that redirects every request back to itself over plain
# http, for the redirect limit and the no-downgrade rule.
def redirect_loop_server
  counting_server do |socket, _req, p|
    socket.write(http_response('', status: '302 Found', headers: { 'Location' => loopback_url(p, '/') }))
  end
end

# The plain-http URL of a loopback server.
def loopback_url(port, path = '/')
  "http://127.0.0.1:#{port}#{path}"
end

# A loopback stand-in for DHH::Avatars::BASE_URL.
def avatar_base_url(port)
  loopback_url(port, '/x/')
end

# ---- PNG fixtures ----

def png_chunk(type, data)
  [data.bytesize].pack('N') + type + data + [Zlib.crc32(type + data)].pack('N')
end

PNG_SIGNATURE = DHH::UntrustedImage::PNG_SIGNATURE
PNG_IHDR = png_chunk('IHDR', [8, 8, 8, 2, 0, 0, 0].pack('NNC5'))
PNG_IEND = png_chunk('IEND', ''.b)
CLEAN_PNG = PNG_SIGNATURE + PNG_IHDR + PNG_IEND
# A zTXt chunk whose payload inflates ~1000x: a multi-MB allocation if decoded.
BOMB_PNG = PNG_SIGNATURE + PNG_IHDR +
           png_chunk('zTXt', "Comment\x00\x00".b + Zlib::Deflate.deflate('B' * 500_000)) +
           PNG_IEND
MALFORMED_PNG = PNG_SIGNATURE + 'not a chunk stream'
# A valid PNG whose IHDR claims 100000x100000 pixels: 45 bytes on the wire, a
# 40 GB decode.
HUGE_PNG = PNG_SIGNATURE + png_chunk('IHDR', [100_000, 100_000, 8, 2, 0, 0, 0].pack('NNC5')) + PNG_IEND

# A clean PNG padded with a tEXt chunk to a chosen size, for the byte budgets.
def padded_png(extra)
  PNG_SIGNATURE + PNG_IHDR + png_chunk('tEXt', 'p' * extra) + PNG_IEND
end

# ---- other image fixtures (headers only; the sniffer reads no pixels) ----

# SOI, a baseline SOF0 for an 8x8 3-component frame, EOI.
TINY_JPEG = "\xFF\xD8".b + "\xFF\xC0".b + [17, 8, 8, 8, 3].pack('nCnnC') + ("\x01\x11\x00".b * 3) + "\xFF\xD9".b
TINY_GIF = 'GIF89a'.b + [8, 8].pack('vv') + "\x00\x00\x00;".b
# Lossless WebP: VP8L signature byte then the 14-bit width-1 / height-1 fields (8x8).
TINY_WEBP = 'RIFF'.b + [18].pack('V') + 'WEBP'.b + 'VP8L'.b + [6].pack('V') + "\x2F".b + [7, 0xC0, 0x01, 0x00].pack('C4') + "\x00".b
TINY_SVG = '<svg xmlns="http://www.w3.org/2000/svg" width="8" height="8"/>'

def decode_data_uri(uri)
  uri.sub(/\Adata:[^,]*,/, '').unpack1('m0')
end
