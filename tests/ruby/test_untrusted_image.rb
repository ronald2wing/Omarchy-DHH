# DHH::UntrustedImage: the PNG bomb filter, the byte sniffer, the pixel cap and the data URI.

require_relative 'test_helper'

UntrustedImage = DHH::UntrustedImage

assert(UntrustedImage.strip_png_bomb_chunks(CLEAN_PNG) == CLEAN_PNG, 'strip: clean PNG unchanged')
assert(UntrustedImage.strip_png_bomb_chunks("\xff\xd8\xff\xe0jpeg".b) == "\xff\xd8\xff\xe0jpeg".b, 'strip: non-PNG bytes pass through')
assert(UntrustedImage.strip_png_bomb_chunks(PNG_SIGNATURE).nil?, 'strip: signature-only fails closed')

text_chunk = png_chunk('tEXt', "Keep\x00value".b)
loaded = PNG_SIGNATURE + PNG_IHDR +
         png_chunk('zTXt', "Comment\x00\x00".b + Zlib::Deflate.deflate('A' * 1_000_000)) +
         png_chunk('iTXt', "k\x00\x00\x00\x00\x00text".b) +
         png_chunk('iCCP', "prof\x00\x00".b + Zlib::Deflate.deflate('p' * 4_000)) +
         text_chunk + PNG_IEND
assert(UntrustedImage.strip_png_bomb_chunks(loaded) == PNG_SIGNATURE + PNG_IHDR + text_chunk + PNG_IEND,
       'strip: zTXt/iTXt/iCCP dropped, other chunks byte-identical')
assert(UntrustedImage.strip_png_bomb_chunks(PNG_SIGNATURE + "\x00\x00\x00\x20zTXtshort".b).nil?, 'strip: chunk overrun fails closed')
assert(UntrustedImage.strip_png_bomb_chunks(PNG_SIGNATURE + PNG_IHDR).nil?, 'strip: missing IEND fails closed')
assert(UntrustedImage.strip_png_bomb_chunks(CLEAN_PNG + 'trailing').nil?, 'strip: trailing bytes fail closed')

assert(UntrustedImage.data_uri(PNG_SIGNATURE).nil?, 'data_uri: unparseable PNG -> nil')
assert(decode_data_uri(UntrustedImage.data_uri(BOMB_PNG)) == CLEAN_PNG, 'data_uri: encodes the stripped bytes')
assert(UntrustedImage.data_uri('abc').nil? && UntrustedImage.data_uri(TINY_SVG).nil?, 'data_uri: non-image bytes -> nil')
assert(UntrustedImage.data_uri(HUGE_PNG).nil?, 'data_uri: over the pixel cap -> nil')
assert(UntrustedImage.sniff(CLEAN_PNG) == ['image/png', 8, 8], 'sniff: PNG')
assert(UntrustedImage.sniff(TINY_JPEG) == ['image/jpeg', 8, 8], 'sniff: JPEG')
assert(UntrustedImage.sniff(TINY_GIF) == ['image/gif', 8, 8], 'sniff: GIF')
assert(UntrustedImage.sniff(TINY_WEBP) == ['image/webp', 8, 8], 'sniff: WebP lossless')
assert(UntrustedImage.sniff("\xFF\xD8\xFF\xC0\x00".b).nil? && UntrustedImage.sniff('RIFFxxxxWEBPVP8 ').nil?, 'sniff: truncated headers -> nil')

big = padded_png(100)
assert(UntrustedImage.data_uri(big) == "data:image/png;base64,#{[big].pack('m0')}", 'data_uri: strict base64, no newlines')
assert(UntrustedImage.data_uri(TINY_GIF).start_with?('data:image/gif;base64,'), 'data_uri: labelled with the sniffed type')

puts 'test_untrusted_image.rb: all assertions passed'
