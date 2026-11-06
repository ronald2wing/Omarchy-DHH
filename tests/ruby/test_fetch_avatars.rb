# helpers/fetch-avatars end to end against loopback servers.

require 'open3'
require_relative 'test_helper'
HELPER = File.join(ROOT, 'helpers', 'fetch-avatars')
load HELPER

FetchAvatars = DHH::FetchAvatars
def handle_of(req) = req.split(' ')[1].split('/').last
def png_response(body) = http_response(body, type: 'image/png')

# 1. Batch byte budget: the overflowing avatar is fetched then discarded.
server, port, thread, connections = counting_server do |socket, req, _port|
  socket.write(png_response(handle_of(req) == 'aa' ? CLEAN_PNG : padded_png(100)))
end
result = FetchAvatars.batch(%w[aa bb cc], base_url: avatar_base_url(port), max_batch_bytes: CLEAN_PNG.bytesize + 50)
assert(result.keys == ['aa'], 'only the first avatar fits the budget')
server.close
thread.join
assert(connections.call == 2, 'the overflowing avatar is fetched, then the batch stops')

# 2. Partial success: a failing handle is omitted, the rest map to data URIs;
# PNG bomb chunks are stripped and a malformed PNG is dropped.
bodies = { 'bomb' => BOMB_PNG, 'clean' => CLEAN_PNG, 'broken' => MALFORMED_PNG }
server, port, thread = accepting_server do |socket, req, _p|
  body = bodies[handle_of(req)]
  socket.write(body ? png_response(body) : http_response('error', status: '500 Internal Server Error'))
end
result = FetchAvatars.batch(%w[bomb clean broken bad], base_url: avatar_base_url(port))
assert(result.keys.sort == %w[bomb clean], 'failing and malformed avatars are omitted')
assert(decode_data_uri(result['bomb']) == CLEAN_PNG, 'bomb chunk stripped')
assert(decode_data_uri(result['clean']) == CLEAN_PNG, 'clean PNG byte-identical')
server.close
thread.join

# 3. The shared deadline bounds a slow-trickling server across the batch.
server, port, thread, connections = counting_server do |socket, _req, _p|
  socket.write("HTTP/1.1 200 OK\r\nContent-Type: image/png\r\n\r\n")
  loop do
    socket.write('x' * 512)
    sleep 2
  end
rescue Errno::EPIPE, Errno::ECONNRESET, IOError
  # expected
end
t0 = Time.now
FetchAvatars.batch(%w[a b c d], base_url: avatar_base_url(port), deadline: DHH::Deadline.after(1), max_avatar_bytes: 1_000_000, max_batch_bytes: 10_000_000)
assert(Time.now - t0 < 2, 'batch deadline bounds the whole batch')
server.close
thread.join
assert(connections.call < 4, 'deadline stops the batch early')

# 4. CLI: --help, the handle cap, an unknown flag, and an empty batch (no
# network) printing the JSON contract.
out, status = Open3.capture2(HELPER, '--help')
assert(status.success? && out.start_with?('usage:'), 'fetch-avatars --help')
_out, err, status = Open3.capture3(HELPER, *(['a'] * (FetchAvatars::MAX_HANDLES + 1)))
assert(status.exitstatus == 1 && err.include?('too many handles') && err.include?('usage: helpers/fetch-avatars'),
       'fetch-avatars caps the handle count')
_out, err, status = Open3.capture3(HELPER, '--bogus')
assert(status.exitstatus == 1 && err.include?('unknown flag: --bogus'), 'fetch-avatars rejects unknown flags')
out, status = Open3.capture2(HELPER, '@../etc', 'a b')
assert(status.success? && out == "{}\n", 'invalid handles print an empty JSON object')

puts 'test_fetch_avatars.rb: all assertions passed'
