# DHH::UntrustedImage: fetched bytes to a data URI, or nil: type sniffing, the pixel cap, the PNG bomb filter.

module DHH
  module UntrustedImage
    # Pixel cap on a fetched image (2048x2048). Qt decodes a PNG at full size
    # before scaling it to the avatar's sourceSize, so a sub-1 MiB file of
    # flat color could otherwise claim hundreds of MB inside the shell.
    MAX_PIXELS = 2048 * 2048
    PNG_SIGNATURE = "\x89PNG\r\n\x1a\n".b.freeze
    GIF_SIGNATURES = ["GIF87a".b, "GIF89a".b].freeze
    JPEG_SIGNATURE = "\xFF\xD8\xFF".b.freeze
    # JPEG start-of-frame markers (baseline through lossless and differential),
    # the segment that carries the image dimensions.
    JPEG_SOF_MARKERS = [0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7,
                        0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF].freeze
    VP8_START_CODE = "\x9D\x01\x2A".b.freeze
    # PNG chunks libpng inflates eagerly (up to 8 MB each, all retained by Qt).
    PNG_BOMB_CHUNKS = %w[zTXt iTXt iCCP].freeze

    module_function

    # The data URI for fetched image bytes, or nil unless they are a PNG, GIF,
    # JPEG or WebP within MAX_PIXELS. A PNG is bomb-stripped and fails closed
    # when it does not parse. The label comes from the sniffed type, never
    # from the response.
    def data_uri(bytes)
      mime, width, height = sniff(bytes)
      return nil unless mime
      return nil if width <= 0 || height <= 0 || width * height > MAX_PIXELS

      stripped = strip_png_bomb_chunks(bytes)
      stripped && encode(mime, stripped)
    end

    # [mime, width, height] read from the header of PNG, GIF, JPEG or WebP
    # bytes; nil for anything else. Qt picks the decoder from the bytes, never
    # from the data URI's label or the response's Content-Type, so the type is
    # sniffed the same way here: an SVG (or any other format an installed Qt
    # plugin might decode) labelled image/png is rejected, not relabelled.
    def sniff(bytes)
      data = bytes.b
      if data.start_with?(PNG_SIGNATURE)
        return nil if data.bytesize < 24 || data.byteslice(12, 4) != 'IHDR'

        width, height = data.byteslice(16, 8).unpack('NN')
        ['image/png', width, height]
      elsif GIF_SIGNATURES.any? { |sig| data.start_with?(sig) }
        return nil if data.bytesize < 10

        width, height = data.byteslice(6, 4).unpack('vv')
        ['image/gif', width, height]
      elsif data.start_with?(JPEG_SIGNATURE)
        jpeg_dimensions(data)
      elsif data.start_with?('RIFF'.b) && data.byteslice(8, 4) == 'WEBP'
        webp_dimensions(data)
      end
    end

    # Strips the zTXt/iTXt/iCCP chunks from a PNG byte stream: a sub-1 MiB
    # avatar carrying them can force multi-GB allocations in the shell, and
    # avatars never need them. Non-PNG bytes pass through; a PNG that does not
    # walk cleanly returns nil so the caller fails the fetch — bytes a decoder
    # might tolerate must never bypass this.
    def strip_png_bomb_chunks(bytes)
      data = bytes.b
      return bytes unless data.start_with?(PNG_SIGNATURE)

      out = PNG_SIGNATURE.dup
      pos = PNG_SIGNATURE.bytesize
      loop do
        remaining = data.bytesize - pos
        return nil if remaining < 12

        total = data.byteslice(pos, 4).unpack1('N') + 12
        return nil if total > remaining

        type = data.byteslice(pos + 4, 4)
        out << data.byteslice(pos, total) unless PNG_BOMB_CHUNKS.include?(type)
        pos += total
        break if type == 'IEND'
      end
      pos == data.bytesize ? out : nil
    end

    # A strict-base64 data URI (no line breaks).
    def encode(mime, bytes)
      "data:#{mime};base64,#{[bytes].pack('m0')}"
    end

    # Walk the JPEG marker segments to the first start-of-frame.
    def jpeg_dimensions(data)
      pos = 2
      while pos + 4 <= data.bytesize
        return nil unless data.getbyte(pos) == 0xFF

        marker = data.getbyte(pos + 1)
        if marker == 0xFF
          pos += 1 # fill byte
          next
        end
        if marker == 0x01 || (0xD0..0xD9).cover?(marker)
          pos += 2 # standalone marker, no length
          next
        end
        length = data.byteslice(pos + 2, 2).unpack1('n')
        return nil if length < 2

        if JPEG_SOF_MARKERS.include?(marker)
          return nil if pos + 9 > data.bytesize

          height, width = data.byteslice(pos + 5, 4).unpack('nn')
          return ['image/jpeg', width, height]
        end
        pos += 2 + length
      end
      nil
    end

    # The canvas size from the first WebP chunk: lossy (VP8 ), lossless
    # (VP8L) or extended (VP8X).
    def webp_dimensions(data)
      case data.byteslice(12, 4)
      when 'VP8 '
        return nil if data.bytesize < 30 || data.byteslice(23, 3) != VP8_START_CODE

        width, height = data.byteslice(26, 4).unpack('vv')
        ['image/webp', width & 0x3FFF, height & 0x3FFF]
      when 'VP8L'
        return nil if data.bytesize < 25 || data.getbyte(20) != 0x2F

        b0, b1, b2, b3 = data.byteslice(21, 4).unpack('C4')
        width = 1 + (b0 | ((b1 & 0x3F) << 8))
        height = 1 + ((b1 >> 6) | (b2 << 2) | ((b3 & 0x0F) << 10))
        ['image/webp', width, height]
      when 'VP8X'
        return nil if data.bytesize < 30

        width = 1 + (data.byteslice(24, 3) + "\x00".b).unpack1('V')
        height = 1 + (data.byteslice(27, 3) + "\x00".b).unpack1('V')
        ['image/webp', width, height]
      end
    end

    private_class_method :encode, :jpeg_dimensions, :webp_dimensions
  end
end
