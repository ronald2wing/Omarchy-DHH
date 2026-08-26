// Shared DHH format helpers for the render pipeline. Locale- and Qt-free so
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

// 32-bit FNV-1a hash of a string, whose output engagementCounts reads as four
// 8-bit chunks. Marked private: only engagementCounts calls it.
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
function formatCount(n) {
  if (n < 1000) return String(n)
  const div = n >= 1000000 ? 1000000 : 1000
  const unit = n >= 1000000 ? "M" : "K"
  const v = n / div
  const rounded = v < 10 ? Math.round(v * 10) / 10 : Math.round(v)
  return String(rounded) + unit
}

// X profile-stat count: one decimal for K/M ("72.4K", "1.9M"), bare under 1000.
// Intentionally distinct from formatCount — profile stats always keep one
// decimal, while post engagement counts round to whole numbers at/above 10 of a
// unit. The tests assert each rounding separately, so don't merge the two.
function formatPosts(n) {
  if (n < 1000) return String(n)
  const div = n >= 1000000 ? 1000000 : 1000
  const unit = n >= 1000000 ? "M" : "K"
  return String(Math.round((n / div) * 10) / 10) + unit
}

// Deterministic per-entry engagement counts so the panel and the rendered
// image show identical numbers for the same text. The text's FNV-1a hash is
// split into four 8-bit chunks, each scaled into X-plausible ranges (reply
// smallest, views largest). Display-only decor.
function engagementCounts(text) {
  const h = _hash32(String(text || ""))
  return {
    reply: 50 + Math.round(((h & 255) / 255) * 850),
    repost: 500 + Math.round((((h >>> 8) & 255) / 255) * 2500),
    like: 2000 + Math.round((((h >>> 16) & 255) / 255) * 78000),
    views: 100000 + Math.round((((h >>> 24) & 255) / 255) * 2900000)
  }
}
