// The Qt/OS boundary: file URLs as paths, UTF-8 byte lengths for the byte caps.

// A "file://" URL as a filesystem path; input without the scheme passes
// through. A malformed %-escape keeps the undecoded path, which is the right
// answer for a value only ever used to open a local file.
export function fileUrlToPath(url) {
  let s = String(url || "")
  if (!s.startsWith("file://")) return s
  s = s.substring(7)
  if (s.charAt(0) !== "/") s = "/" + s
  try { return decodeURIComponent(s) } catch (e) { return s }
}

// UTF-8 byte length. argv and transport limits are in bytes, not UTF-16
// units: emoji is 4 bytes for 2 units, so `s.length` undercounts. null and
// undefined count as "", so a missing helper output is 0 bytes.
export function utf8ByteLength(s) {
  const str = s == null ? "" : String(s)
  let bytes = 0
  for (let i = 0; i < str.length; i++) {
    const code = str.charCodeAt(i)
    if (code < 0x80) bytes += 1
    else if (code < 0x800) bytes += 2
    else if (code < 0xD800 || code >= 0xE000) bytes += 3
    else { bytes += 4; i++ }
  }
  return bytes
}
