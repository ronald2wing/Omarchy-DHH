# DHH::Avatars: the avatar policy behind helpers/fetch-avatars: valid handles, the URI, one bounded fetch.

require 'uri'

module DHH
  module Avatars
    # x.com's handle alphabet and length. Only a handle matching this is ever
    # interpolated into a URL. Entries.isValidHandle (js/entries.mjs) mirrors
    # it as the panel's pre-filter.
    HANDLE_PATTERN = /\A[A-Za-z0-9_]{1,15}\z/
    # Per-avatar body cap: the streaming reader aborts the instant a body
    # crosses it.
    MAX_AVATAR_BYTES = 1024 * 1024
    BASE_URL = 'https://unavatar.io/x/'
    # Per-hop timeout; each hop is also clipped to the caller's deadline.
    HTTP_TIMEOUT = 3

    module_function

    def valid_handle?(handle)
      handle.is_a?(String) && HANDLE_PATTERN.match?(handle)
    end

    # The avatar URI for a bare handle, or nil for an invalid one. base_url
    # is overridable so the tests can point it at a loopback server.
    def uri_for(handle, base_url: BASE_URL)
      return nil unless valid_handle?(handle)

      URI("#{base_url}#{URI.encode_uri_component(handle)}")
    end

    # One avatar as { data_uri:, bytes: raw body size }, or nil on any
    # failure: invalid handle, expired deadline, non-2xx, transport error,
    # timeout, redirect limit, oversized body, bytes that are not a PNG, GIF,
    # JPEG or WebP within the pixel cap, or a PNG that does not parse (the
    # bomb filter fails closed). `deadline` is a DHH::Deadline.
    def fetch(handle, deadline:, base_url: BASE_URL, max_avatar_bytes: MAX_AVATAR_BYTES)
      uri = uri_for(handle, base_url: base_url)
      return nil if uri.nil? || deadline.expired?

      body = DHH::HTTP.get(uri, max_body_bytes: max_avatar_bytes, timeout: HTTP_TIMEOUT,
                                deadline: deadline, accept: 'image/*')
      data_uri = body && DHH::UntrustedImage.data_uri(body)
      data_uri && { data_uri: data_uri, bytes: body.bytesize }
    end
  end
end
