// Shared DHH format helpers (dates, counts, HTML escape/highlight). Locale- and Qt-free so
// they load via `import "format.js" as Fmt` in QML and `vm` in node scripts
// and tests.

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;")
}

const _MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

// X-style relative/abbreviated date: "5h" for <24h, "2d" for <7d, "Aug 14"
// (month+day) for the current year, and "Dec 7, 2020" (month+day+year) for
// prior years. Returns "" for anything unparseable. The "· " separator is
// prepended by the handle markup, not here.
function formatDate(date) {
  if (!date) return ""
  const m = String(date).match(/^(\d{4})-(\d{2})-(\d{2})$/)
  if (!m) return ""
  const month = _MONTHS[parseInt(m[2], 10) - 1]
  if (!month) return ""
  const day = parseInt(m[3], 10)
  const year = parseInt(m[1], 10)
  const then = new Date(year, parseInt(m[2], 10) - 1, day)
  const now = new Date()
  const diffMs = now.getTime() - then.getTime()
  if (diffMs >= 0 && diffMs < 7 * 24 * 60 * 60 * 1000) {
    const hours = Math.floor(diffMs / (60 * 60 * 1000))
    if (hours < 24) return hours + "h"
    return Math.floor(hours / 24) + "d"
  }
  if (year === now.getFullYear()) return month + " " + day
  return month + " " + day + ", " + year
}

// 32-bit FNV-1a hash of a string, whose output decorativeEngagementCounts reads as four
// 8-bit chunks. NOT canonical FNV-1a: JS multiplies with IEEE-754 doubles
// (implicitly rounding for products > 2^53) then applies >>> 0, so it must
// stay byte-consistent with the Ruby port (DHHHelpers.hash32 in
// bin/dhh_helpers.rb). Called by decorativeEngagementCounts and directly by
// tests/test_format.js.
function _hash32(s) {
  let h = 2166136261
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i)
    h = (h * 16777619) >>> 0
  }
  return h >>> 0
}

// X-style count: bare number under 1000 ("514"), one decimal below 10 of a
// unit ("7.8K", "1.8M"), no decimal at or above it ("12K", "3M").
function formatEngagementCount(n) {
  if (n < 1000) return String(n)
  const div = n >= 1000000 ? 1000000 : 1000
  const unit = n >= 1000000 ? "M" : "K"
  const v = n / div
  const rounded = v < 10 ? Math.round(v * 10) / 10 : Math.round(v)
  return String(rounded) + unit
}

// X profile-stat count: one decimal for K/M ("72.4K", "1.9M"), bare under 1000.
// Intentionally distinct from formatEngagementCount — profile stats always keep one
// decimal, while post engagement counts round to whole numbers at/above 10 of a
// unit. The tests assert each rounding separately, so don't merge the two.
function formatProfileCount(n) {
  if (n < 1000) return String(n)
  const div = n >= 1000000 ? 1000000 : 1000
  const unit = n >= 1000000 ? "M" : "K"
  return String(Math.round((n / div) * 10) / 10) + unit
}

// Deterministic per-entry engagement counts so the panel and the rendered
// image show identical numbers for the same text. The text's FNV-1a hash is
// split into four 8-bit chunks, each scaled into X-plausible ranges (reply
// smallest, views largest). Display-only decor.
function decorativeEngagementCounts(text) {
  const h = _hash32(String(text || ""))
  return {
    reply: 50 + Math.round(((h & 255) / 255) * 850),
    repost: 500 + Math.round((((h >>> 8) & 255) / 255) * 2500),
    like: 2000 + Math.round((((h >>> 16) & 255) / 255) * 78000),
    views: 100000 + Math.round((((h >>> 24) & 255) / 255) * 2900000)
  }
}

// UTF-8 byte length of a string. The render payload travels as a single argv
// argument and Linux caps one argument near 128 KiB of UTF-8 bytes (not UTF-16
// code units) — emoji in imported text is 4 bytes for 2 units, so measuring
// `s.length` would undercount.
function utf8ByteLength(s) {
  let bytes = 0
  for (let i = 0; i < s.length; i++) {
    const code = s.charCodeAt(i)
    if (code < 0x80) bytes += 1
    else if (code < 0x800) bytes += 2
    else if (code < 0xD800 || code >= 0xE000) bytes += 3
    else { bytes += 4; i++ } // surrogate pair -> one 4-byte code point
  }
  return bytes
}

// True when `s` is within `max` UTF-8 bytes. QML-only guard for remote response
// bodies: deliberately NOT ported to bin/dhh_helpers.rb, so it stays off the
// JS<->Ruby parity surface.
function isWithinByteLimit(s, max) {
  return utf8ByteLength(String(s || "")) <= max
}

// Bounded regex cache for highlightHtml, keyed by the lowercased query. A long
// session could otherwise grow it without bound; once it reaches the cap the
// cache is cleared whole (the compiled patterns are tiny and cheap to rebuild).
var _highlightPatternCache = Object.create(null)
const _HIGHLIGHT_CACHE_MAX = 64

function _escapeRegex(s) {
  return String(s).replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
}

// Wrap each case-insensitive match of `query` in `<b>…</b>` inside an HTML-
// escaped copy of `text`. The match runs against the RAW text and each segment
// (and the matched span) is escaped separately, so a query containing & < >
// still matches, while words like "amp"/"lt"/"quot" do not spuriously match
// inside escaped HTML entities. An empty query returns the escaped text with no
// highlighting.
function highlightHtml(text, query) {
  const t = String(text || "")
  const q = String(query || "").trim()
  if (q === "") return escapeHtml(t)
  const key = q.toLowerCase()
  let re = _highlightPatternCache[key]
  if (re === undefined) {
    if (Object.keys(_highlightPatternCache).length >= _HIGHLIGHT_CACHE_MAX) {
      _highlightPatternCache = Object.create(null)
    }
    const words = key.split(/\s+/)
    re = new RegExp("(" + words.map(_escapeRegex).join("|") + ")", "gi")
    _highlightPatternCache[key] = re
  }
  let out = ""
  let last = 0
  let m
  re.lastIndex = 0
  while ((m = re.exec(t)) !== null) {
    out += escapeHtml(t.slice(last, m.index)) + "<b>" + escapeHtml(m[0]) + "</b>"
    last = m.index + m[0].length
  }
  out += escapeHtml(t.slice(last))
  return out
}
