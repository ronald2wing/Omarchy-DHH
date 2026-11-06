// Display formatting: escaping, dates, counts, the handle line and the verified seal.

export function escapeHtml(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;")
}

// The inverse of escapeHtml: its five entities back to their characters,
// "&amp;" last so "&amp;lt;" reads as "&lt;".
export function unescapeHtml(s) {
  return String(s)
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, "\"")
    .replace(/&#39;/g, "'")
    .replace(/&amp;/g, "&")
}

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

// x.com's date for a "YYYY-MM-DD" day, seen at `now`: the hours since that
// day's local midnight under 24 ("5h"), the days under 7 ("2d"), "Aug 14"
// for the current year, "Dec 7, 2020" for earlier years. "" for anything
// unparseable.
export function formatDate(date, now = new Date()) {
  const m = String(date).match(/^(\d{4})-(\d{2})-(\d{2})$/)
  if (!m) return ""
  const month = MONTHS[parseInt(m[2], 10) - 1]
  if (!month) return ""
  const day = parseInt(m[3], 10)
  const year = parseInt(m[1], 10)
  const then = new Date(year, parseInt(m[2], 10) - 1, day)
  const diffMs = now.getTime() - then.getTime()
  if (diffMs >= 0 && diffMs < 7 * 24 * 60 * 60 * 1000) {
    const hours = Math.floor(diffMs / (60 * 60 * 1000))
    if (hours < 24) return hours + "h"
    return Math.floor(hours / 24) + "d"
  }
  if (year === now.getFullYear()) return month + " " + day
  return month + " " + day + ", " + year
}

// 32-bit FNV-1a over UTF-16 code units. NOT canonical FNV-1a: the multiply
// runs in IEEE-754 doubles (rounding above 2^53) before `>>> 0`. The
// decorative counts and image names derive from it, so keep it exactly as is.
export function hash32(s) {
  let h = 2166136261
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i)
    h = (h * 16777619) >>> 0
  }
  return h >>> 0
}

// Abbreviate with K/M. `wholeFrom10` drops the decimal at or above 10 of a
// unit ("12K"); otherwise one decimal is kept at every magnitude ("72.4K").
function abbreviateCount(n, wholeFrom10) {
  if (n < 1000) return String(n)
  const div = n >= 1000000 ? 1000000 : 1000
  const unit = n >= 1000000 ? "M" : "K"
  const v = n / div
  const rounded = wholeFrom10 && v >= 10 ? Math.round(v) : Math.round(v * 10) / 10
  return String(rounded) + unit
}

// Post engagement count, as x.com shows it: "514", "7.8K", "12K", "3M".
export function formatEngagementCount(n) {
  return abbreviateCount(n, true)
}

// DHH's post count in the profile header, which keeps one decimal: "72.4K",
// "1.9M". Panel-only; the rendered image shows no post count.
export function formatPostCount(n) {
  return abbreviateCount(n, false)
}

// Deterministic per-text engagement counts so the panel and the rendered
// image agree. The hash splits into four 8-bit chunks scaled into plausible
// ranges (replies smallest, views largest). Display-only decor. The keys are
// the action-row icon names.
export function decorativeEngagementCounts(text) {
  const h = hash32(String(text || ""))
  return {
    reply: 50 + Math.round(((h & 255) / 255) * 850),
    repost: 500 + Math.round((((h >>> 8) & 255) / 255) * 2500),
    like: 2000 + Math.round((((h >>> 16) & 255) / 255) * 78000),
    views: 100000 + Math.round((((h >>> 24) & 255) / 255) * 2900000)
  }
}

// An author line's handle and date: "@dhh · Dec 7, 2020", or the handle alone
// when the date is missing or unparseable. Plain text.
export function handleLine(handle, date) {
  const formatted = formatDate(date)
  return (handle == null ? "" : String(handle)) + (formatted ? " \u00b7 " + formatted : "")
}

// The verified seal's icon for a verification type: organization gold,
// government grey, individual (or unknown) blue; a name under assets/icons.
export function sealIconName(verifiedType) {
  if (verifiedType === "organization") return "verified-gold"
  if (verifiedType === "government") return "verified-grey"
  return "verified-blue"
}
