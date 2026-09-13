# Shared DHH helpers for the Ruby scripts in bin/. This is the Ruby port of the
# Qt-free helpers in search.js and format.js, and must reproduce their behavior
# byte-for-byte (including the places where the JS is quirky: _hash32 is not
# canonical FNV-1a because JS multiplies with IEEE-754 doubles, and formatEngagementCount
# relies on JS Number-to-String dropping a trailing ".0"). Stdlib only.
#
# Shared HTTP transport for the network helpers (DHHFetch below): byte-capped,
# deadline-bound, TLS-verified fetches with a common redirect policy. `net/http`
# is required lazily inside DHHFetch.fetch, so local-only tools
# (omarchy-add-entry, omarchy-sort-data) that require this file never load it.

require 'digest'

module DHHHelpers
  module_function

  # Repo root (bin/..) and the dataset path, shared by the bin/ CLIs.
  SCRIPT_ROOT = File.expand_path('..', __dir__)
  DATA_FILE = File.join(SCRIPT_ROOT, 'data', 'quotes.jsonl')

  # Shared CLI failure path: report on stderr and exit non-zero.
  def die(msg)
    warn(msg)
    exit 1
  end

  # Strict exact-match YYYY-MM-DD. \z anchors to the true end of the string, so
  # a trailing newline is rejected (Ruby \Z would tolerate one). All dates in
  # data/quotes.jsonl are exact, so the strict form is the safe choice.
  DATE_RE = /\A\d{4}-\d{2}-\d{2}\z/

  # String(text).trim().toLowerCase().replace(/\s+/g, " ")
  def normalize(text)
    text.to_s.strip.downcase.gsub(/\s+/, ' ')
  end

  # First 8 hex chars of the SHA-256 of normalize(text).
  def entry_id(text)
    Digest::SHA256.hexdigest(normalize(text))[0, 8]
  end

  # String(text || "").toLowerCase().replace(/[^a-z0-9]+/g, "-")
  #   .replace(/^-+|-+$/g, "").slice(0, 60)
  # The trailing slice is over an already-ASCII string (only [a-z0-9-] remain),
  # so Ruby character slicing equals JS UTF-16-code-unit slicing here.
  def slugify(text)
    text.to_s
        .downcase
        .gsub(/[^a-z0-9]+/, '-')
        .gsub(/\A-+|-+\z/, '')
        .slice(0, 60)
  end

  # if (!text || !handle) return text; text.replace(/^(?:@[\w]+\s+)+/, "")
  def strip_leading_mentions(text, handle)
    return text if text.nil? || text.empty? || handle.nil? || handle.empty?

    text.sub(/^(?:@\w+\s+)+/, '')
  end

  # String(s) with the replacements applied in this exact order (& first).
  def escape_html(str)
    str.to_s
       .gsub('&', '&amp;')
       .gsub('<', '&lt;')
       .gsub('>', '&gt;')
       .gsub('"', '&quot;')
       .gsub("'", '&#39;')
  end

  # _hash32 in format.js is NOT canonical FNV-1a: JS multiplies with IEEE-754
  # doubles (implicitly rounding for products > 2^53) and applies >>> 0, so a
  # plain Ruby integer FNV diverges on ~69% of inputs. This reproduces the JS
  # ToInt32-at-XOR and double-multiply-then-ToUint32 steps exactly.
  def hash32(s)
    h = 2_166_136_261
    s.encode('UTF-16LE').unpack('v*').each do |u|     # JS charCodeAt = UTF-16 code units
      hi = h >= 2**31 ? h - 2**32 : h                 # emulate JS ToInt32 at the XOR
      h = ((hi ^ u).to_f * 16_777_619.0).to_i % (2**32) # double multiply, then ToUint32
    end
    h
  end

  # formatEngagementCount: bare number under 1000, one decimal below 10 of a unit, no
  # decimal at or above it. Replicates JS Number-to-String semantics, where
  # String(2.0) is "2" but Ruby 2.0.to_s is "2.0".
  def format_engagement_count(n)
    return n.to_s if n < 1000

    div, unit = n >= 1_000_000 ? [1_000_000, 'M'] : [1000, 'K']
    v = n.to_f / div
    r = v < 10 ? (v * 10).round / 10.0 : v.round
    (r == r.to_i ? r.to_i.to_s : r.to_s) + unit
  end

  # decorativeEngagementCounts: split the FNV-1a hash into four 8-bit chunks scaled into
  # X-plausible ranges. Display-only decor; deterministic per text.
  def decorative_engagement_counts(text)
    h = hash32(text.to_s)
    {
      reply: 50 + (((h & 255) / 255.0) * 850).round,
      repost: 500 + ((((h >> 8) & 255) / 255.0) * 2500).round,
      like: 2000 + ((((h >> 16) & 255) / 255.0) * 78_000).round,
      views: 100_000 + ((((h >> 24) & 255) / 255.0) * 2_900_000).round
    }
  end

  MONTHS = %w[Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec].freeze

  # formatDate: "5h" under 24h, "2d" under 7d, "Aug 14" this year, "Dec 7, 2020"
  # otherwise; "" for anything unparseable. The regex captures month/day/year and
  # the Date object is used only for the relative window, so the rendered
  # day/month/year come straight from the captured groups.
  def format_date(iso)
    s = iso.to_s
    return '' if s.empty?

    m = s.match(/\A(\d{4})-(\d{2})-(\d{2})\z/)
    return '' unless m

    month_index = m[2].to_i - 1
    return '' unless month_index.between?(0, 11)

    day = m[3].to_i
    year = m[1].to_i
    then_t = Time.local(year, month_index + 1, day)
    now = Time.now
    diff_ms = (now.to_f - then_t.to_f) * 1000
    if diff_ms >= 0 && diff_ms < 7 * 24 * 60 * 60 * 1000
      hours = (diff_ms / (60 * 60 * 1000)).floor
      return "#{hours}h" if hours < 24

      return "#{(hours / 24).floor}d"
    end
    return "#{MONTHS[month_index]} #{day}" if year == now.year

    "#{MONTHS[month_index]} #{day}, #{year}"
  end

  # Remove Ruby/Bundler env vars that could inject code or load paths. RUBYOPT,
  # RUBYLIB, and the rest are applied by the interpreter BEFORE this method
  # runs, so this scrub cannot undo anything already loaded and only bounds
  # child processes and later loads; the hardened shebang is the real control.
  def sanitize_environment!
    %w[RUBYOPT RUBYLIB RUBYGEMS_GEMDEPS GEM_HOME GEM_PATH].each do |k|
      ENV.delete(k)
    end
    ENV.delete_if { |k, _| k.start_with?('BUNDLE_') }
    nil
  end
end

module DHHFetch
  USER_AGENT = 'omarchy-dhh-maintainer/1.0'
  MAX_REDIRECTS = 3
  # Per-avatar body cap shared by the avatar fetcher and the render: the
  # streaming accumulator aborts the instant it crosses this, so a chunked
  # response without a Content-Length cannot balloon memory.
  MAX_AVATAR_BYTES = 1_048_576
  MIME_ALLOWLIST = %r{\Aimage/(png|jpe?g|gif|webp)\z}
  class BodyTooLarge < StandardError; end

  def self.capped_body(response, max_bytes:)
    body = +''
    response.read_body do |chunk|
      body << chunk
      raise BodyTooLarge if body.bytesize > max_bytes
    end
    body
  end

  def self.data_uri(mime, bytes)
    "data:#{mime};base64,#{[bytes].pack('m0')}"
  end

  def self.image_mime(content_type)
    mime = content_type.to_s.split(';').first.to_s.strip
    MIME_ALLOWLIST.match?(mime) ? mime : 'image/png'
  end

  def self.image_data_uri(content_type, bytes)
    data_uri(image_mime(content_type), bytes)
  end

  # Returns the block's value on 2xx, nil on any failure.
  # timeout: per-hop open/read/write/ssl seconds.
  # deadline: remaining wall-clock seconds for this fetch (nil = unbounded);
  #           each hop is clipped to what remains.
  def self.fetch(uri, max_bytes:, timeout:, max_redirects: MAX_REDIRECTS,
                 accept: nil, user_agent: USER_AGENT, deadline: nil)
    require 'net/http'

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    redirects = 0
    current = uri

    loop do
      remaining = deadline && deadline - (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
      return nil if remaining && remaining <= 0

      hop = remaining ? [timeout, remaining].min : timeout

      result = nil
      next_url = nil

      Net::HTTP.start(
        current.host, current.port,
        use_ssl: current.is_a?(URI::HTTPS),
        open_timeout: hop, read_timeout: hop, write_timeout: hop, ssl_timeout: hop
      ) do |http|
        request = Net::HTTP::Get.new(current.request_uri)
        request['User-Agent'] = user_agent if user_agent
        request['Accept'] = accept if accept
        http.request(request) do |response|
          if response.is_a?(Net::HTTPSuccess)
            result = yield(capped_body(response, max_bytes: max_bytes), response['content-type'])
          elsif response.is_a?(Net::HTTPRedirection)
            redirects += 1
            next if redirects > max_redirects

            location = response['location'].to_s
            next if location.empty?

            target = URI.join(current.to_s, location)
            next_url = target if target.is_a?(URI::HTTPS)
          end
        end
      end

      return result unless result.nil?
      return nil if next_url.nil?

      current = next_url
    end
  rescue StandardError
    nil
  end
end
