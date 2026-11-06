# DHH::Avatars: handle policy, URI, and fetch against loopback servers.

require_relative 'test_helper'

Avatars = DHH::Avatars
def soon = DHH::Deadline.after(5)
def png_response(body) = http_response(body, type: 'image/png')

# Handle policy.
%w[dhh jason_fried A1 _].each { |h| assert(Avatars.valid_handle?(h), "valid handle: #{h}") }
assert(Avatars.valid_handle?('a' * 15) && !Avatars.valid_handle?('a' * 16), 'handles are 1-15 characters')
['', '@dhh', '../etc', 'a b', 'a-b', 'é', "dhh\n", nil, 42].each do |h|
  assert(!Avatars.valid_handle?(h), "invalid handle: #{h.inspect}")
end

# URIs.
assert(Avatars.uri_for('dhh').to_s == 'https://unavatar.io/x/dhh' && Avatars.uri_for('dhh').is_a?(URI::HTTPS), 'uri_for: the HTTPS unavatar.io URI')
assert(Avatars.uri_for('dhh', base_url: 'http://127.0.0.1:9/x/').to_s == 'http://127.0.0.1:9/x/dhh', 'uri_for: base_url override')
assert(Avatars.uri_for('../etc').nil? && Avatars.uri_for('').nil?, 'uri_for: nil for an invalid handle')

# A fetch returns the data URI and the raw size, with an image Accept header.
port, thread = one_shot_server do |socket, req|
  assert(req.start_with?('GET /x/alice ') && req.include?('Accept: image/*'), 'fetch asks for the handle as an image')
  socket.write(png_response(CLEAN_PNG))
end
fetched = Avatars.fetch('alice', deadline: soon, base_url: avatar_base_url(port))
assert(fetched == { data_uri: "data:image/png;base64,#{[CLEAN_PNG].pack('m0')}", bytes: CLEAN_PNG.bytesize }, 'fetch: { data_uri:, bytes: }')
thread.join

# Invalid handles and an expired deadline never open a connection.
server, port, thread, connections = counting_server
['../etc', 'a b', '', 'x' * 16, '@at'].each do |h|
  assert(Avatars.fetch(h, deadline: soon, base_url: avatar_base_url(port)).nil?, "fetch: nil for #{h.inspect}")
end
assert(Avatars.fetch('fine', deadline: DHH::Deadline.after(0), base_url: avatar_base_url(port)).nil?, 'fetch: nil once the deadline has expired')
server.close
thread.join
assert(connections.call.zero?, 'no connection for invalid handles or an expired deadline')

# The knobs reach DHH::HTTP (test_http.rb covers how it enforces them): an
# avatar over max_avatar_bytes is dropped, and the deadline, not the 3 s hop
# timeout, bounds a stalled fetch.
big = padded_png(2048)
port, thread = one_shot_server { |socket, _req| socket.write(png_response(big)) }
assert(Avatars.fetch('big', deadline: soon, base_url: avatar_base_url(port), max_avatar_bytes: 1024).nil?, 'max_avatar_bytes is passed through')
thread.join
port, thread = stalling_server
t0 = Time.now
assert(Avatars.fetch('stall', deadline: DHH::Deadline.after(0.5), base_url: avatar_base_url(port)).nil?, 'stalled fetch returns nil')
assert(Time.now - t0 < 2, 'the deadline is passed through')
thread.join

# The bytes decide, never the Content-Type: an SVG labelled image/png is
# dropped (Qt would decode it from the bytes) and a JPEG labelled text/html
# is served as image/jpeg. test_untrusted_image.rb covers the sniffer itself.
[[TINY_SVG, 'image/png', nil, 'SVG labelled image/png dropped'],
 [TINY_JPEG, 'text/html', 'data:image/jpeg;base64,', 'JPEG labelled text/html relabelled']].each do |body, mime, prefix, label|
  port, thread = one_shot_server { |socket, _req| socket.write(http_response(body, type: mime)) }
  result = Avatars.fetch('mime', deadline: soon, base_url: avatar_base_url(port))
  assert(prefix ? result && result[:data_uri].start_with?(prefix) : result.nil?, label)
  thread.join
end

puts 'test_avatars.rb: all assertions passed'
