# DHH::HTTP: byte-capped, deadline-bound, TLS-verified GET with an HTTPS-only redirect limit.

require 'uri'

module DHH
  module HTTP
    USER_AGENT = "omarchy-dhh/#{DHH::VERSION}".freeze
    MAX_REDIRECTS = 3

    class BodyTooLarge < StandardError; end

    module_function

    # The one request builder: a GET for `path` with the plugin's User-Agent
    # and, when given, an Accept header.
    def request(path, accept:)
      require 'net/http' # lazily, so the local-only tools never load it

      request = Net::HTTP::Get.new(path)
      request['User-Agent'] = USER_AGENT
      request['Accept'] = accept if accept
      request
    end

    # The response body, streamed and aborted with BodyTooLarge the instant it
    # crosses max_body_bytes, so a chunked response without a Content-Length
    # cannot balloon memory.
    def read_capped_body(response, max_body_bytes:)
      body = +''
      response.read_body do |chunk|
        body << chunk
        raise BodyTooLarge if body.bytesize > max_body_bytes
      end
      body
    end

    # GET `uri` and return the body of the 2xx response, following at most
    # MAX_REDIRECTS redirects, and only to HTTPS targets. Returns nil on any
    # failure (every StandardError is absorbed, so callers never rescue).
    #   max_body_bytes: streaming body cap, applied to every response
    #                   including redirect and error bodies (net/http would
    #                   otherwise drain an unread body uncapped).
    #   timeout:        per-hop open/read/write/ssl seconds.
    #   deadline:       a DHH::Deadline for the whole fetch (nil = unbounded);
    #                   each hop is clipped to what remains.
    #   accept:         the Accept header, when given.
    def get(uri, max_body_bytes:, timeout:, deadline: nil, accept: nil)
      require 'net/http' # lazily, so the local-only tools never load it

      redirects = 0
      current = uri

      loop do
        hop = timeout
        if deadline
          remaining = deadline.remaining
          return nil if remaining <= 0

          hop = [timeout, remaining].min
        end
        body = nil
        next_url = nil

        Net::HTTP.start(
          current.host, current.port,
          use_ssl: current.is_a?(URI::HTTPS),
          open_timeout: hop, read_timeout: hop, write_timeout: hop, ssl_timeout: hop
        ) do |http|
          http.request(request(current.request_uri, accept: accept)) do |response|
            capped = read_capped_body(response, max_body_bytes: max_body_bytes)
            if response.is_a?(Net::HTTPSuccess)
              body = capped
            elsif response.is_a?(Net::HTTPRedirection)
              redirects += 1
              next if redirects > MAX_REDIRECTS

              location = response['location'].to_s
              next if location.empty?

              target = URI.join(current.to_s, location)
              next_url = target if target.is_a?(URI::HTTPS)
            end
          end
        end

        return body if body
        return nil unless next_url

        current = next_url
      end
    rescue StandardError
      nil
    end
  end
end
