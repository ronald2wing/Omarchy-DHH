"use strict"
const path = require("path")
const vm = require("vm")

const F = require("./load_script").loadScript(path.join(__dirname, "..", "format.js"))

function assert(cond, msg) {
  if (!cond) throw new Error("FAIL: " + msg)
}

function pad(n) { return n < 10 ? "0" + n : String(n) }
function ymd(d) { return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()) }

// escapeHtml: escapes &, <, >, and both quote characters
assert(F.escapeHtml("<>&\"'") === "&lt;&gt;&amp;&quot;&#39;", "escapeHtml escapes &<> and quotes")
assert(F.escapeHtml("plain text 123") === "plain text 123", "escapeHtml plain text unchanged")

// formatDate: fixed prior year
assert(F.formatDate("2020-12-07") === "Dec 7, 2020", "formatDate prior year")

// formatDate: empty / garbage
assert(F.formatDate("") === "", "formatDate empty string")
assert(F.formatDate(null) === "", "formatDate null")
assert(F.formatDate(undefined) === "", "formatDate undefined")
assert(F.formatDate("not a date") === "", "formatDate garbage")
assert(F.formatDate("2020-13-45") === "", "formatDate invalid month")

// formatDate: relative cases depend on "now", so the expected value is derived
// from the same timestamp the function compares against.
// _MONTHS is a const in format.js, so it isn't a property of the sandbox; read
// it back via the context's lexical scope rather than duplicating the list.
const MONTHS = vm.runInContext("_MONTHS", F)
const now = new Date()

// current year (>7 days ago) omits the year suffix. 30 days back is safely in
// the current year except within the first 30 days of January.
const back30 = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000)
if (back30.getFullYear() === now.getFullYear()) {
  assert(F.formatDate(ymd(back30)) === MONTHS[back30.getMonth()] + " " + back30.getDate(), "formatDate current year omits year")
}

// today -> "Nh" (hours since local midnight)
const midnight = new Date(now.getFullYear(), now.getMonth(), now.getDate())
const hours = Math.floor((now.getTime() - midnight.getTime()) / (60 * 60 * 1000))
assert(F.formatDate(ymd(now)) === hours + "h", "formatDate within 24h")

// 3 days ago -> "3d" (whole days since that date's local midnight)
const back3 = new Date(now.getTime() - 3 * 24 * 60 * 60 * 1000)
const back3Mid = new Date(back3.getFullYear(), back3.getMonth(), back3.getDate())
const back3Hours = Math.floor((now.getTime() - back3Mid.getTime()) / (60 * 60 * 1000))
assert(F.formatDate(ymd(back3)) === Math.floor(back3Hours / 24) + "d", "formatDate within 7d")

// formatEngagementCount
assert(F.formatEngagementCount(157) === "157", "formatEngagementCount under 1000")
assert(F.formatEngagementCount(1900) === "1.9K", "formatEngagementCount one decimal K")
assert(F.formatEngagementCount(29000) === "29K", "formatEngagementCount whole K")
assert(F.formatEngagementCount(3000000) === "3M", "formatEngagementCount whole M")
assert(F.formatEngagementCount(999) === "999", "formatEngagementCount boundary 999")
assert(F.formatEngagementCount(1000) === "1K", "formatEngagementCount boundary 1000")
assert(F.formatEngagementCount(1000000) === "1M", "formatEngagementCount boundary 1M")

// formatProfileCount: one decimal for K/M at any magnitude, bare under 1000
assert(F.formatProfileCount(157) === "157", "formatProfileCount under 1000")
assert(F.formatProfileCount(72434) === "72.4K", "formatProfileCount one decimal K")
assert(F.formatProfileCount(1900) === "1.9K", "formatProfileCount one decimal K low")
assert(F.formatProfileCount(29000) === "29K", "formatProfileCount whole K")
assert(F.formatProfileCount(1900000) === "1.9M", "formatProfileCount one decimal M")
assert(F.formatProfileCount(999) === "999", "formatProfileCount boundary 999")
assert(F.formatProfileCount(1000) === "1K", "formatProfileCount boundary 1000")
assert(F.formatProfileCount(1000000) === "1M", "formatProfileCount boundary 1M")

// decorativeEngagementCounts: deterministic, exactly four numeric values in X-plausible ranges
const t = "determinism probe"
const c1 = F.decorativeEngagementCounts(t)
const c2 = F.decorativeEngagementCounts(t)
assert(c1.reply === c2.reply && c1.repost === c2.repost && c1.like === c2.like && c1.views === c2.views, "decorativeEngagementCounts deterministic")
const keys = Object.keys(c1).sort()
assert(keys.length === 4 && keys[0] === "like" && keys[1] === "reply" && keys[2] === "repost" && keys[3] === "views", "decorativeEngagementCounts four keys")
assert(c1.reply >= 50 && c1.reply <= 900, "decorativeEngagementCounts reply in range")
assert(c1.repost >= 500 && c1.repost <= 3000, "decorativeEngagementCounts repost in range")
assert(c1.like >= 2000 && c1.like <= 80000, "decorativeEngagementCounts like in range")
assert(c1.views >= 100000 && c1.views <= 3000000, "decorativeEngagementCounts views in range")

// decorativeEngagementCounts: empty text still yields a valid hash-based set
const c0 = F.decorativeEngagementCounts("")
assert(typeof c0.reply === "number" && c0.reply >= 50 && c0.reply <= 900, "decorativeEngagementCounts empty text")

// _hash32: deterministic 32-bit unsigned integer (FNV-1a)
assert(F._hash32("abc") === F._hash32("abc"), "_hash32 deterministic")
assert(F._hash32("") === 2166136261, "_hash32 empty = FNV offset basis")
assert(F._hash32("a") === 3826002220, "_hash32 known value 'a'")
assert(F._hash32("abc") === 440920332, "_hash32('abc') known value (JS double-rounded, not canonical FNV)")
const h = F._hash32("abc")
assert(typeof h === "number" && Number.isInteger(h) && h >= 0 && h <= 4294967295, "_hash32 32-bit unsigned")

// utf8ByteLength: ASCII (1 byte/char), 2-byte (é), 3-byte (€), and emoji
// surrogate pairs (4 bytes for 2 code units).
assert(F.utf8ByteLength("") === 0, "utf8ByteLength empty")
assert(F.utf8ByteLength("abc") === 3, "utf8ByteLength ASCII")
assert(F.utf8ByteLength("\u00E9") === 2, "utf8ByteLength 2-byte")
assert(F.utf8ByteLength("\u20AC") === 3, "utf8ByteLength 3-byte")
assert(F.utf8ByteLength("\uD83D\uDCA1") === 4, "utf8ByteLength emoji surrogate pair")
assert(F.utf8ByteLength("a\u00E9\u20AC\uD83D\uDCA1") === 10, "utf8ByteLength mixed")

// isWithinByteLimit: inclusive byte cap over the utf8ByteLength measure.
assert(F.isWithinByteLimit("", 0) === true, "isWithinByteLimit empty within 0")
assert(F.isWithinByteLimit("\u00E9", 2) === true, "isWithinByteLimit 2-byte within 2")
assert(F.isWithinByteLimit("\u00E9", 1) === false, "isWithinByteLimit 2-byte over 1")
assert(F.isWithinByteLimit("\uD83D\uDCA1", 4) === true, "isWithinByteLimit 4-byte emoji within 4")
assert(F.isWithinByteLimit("\uD83D\uDCA1", 3) === false, "isWithinByteLimit 4-byte emoji over 3")

// highlightHtml: match against the RAW text, then escape each segment (and the
// matched span) separately, wrapping matches in <b>…</b>.
assert(F.highlightHtml("hello <world>", "") === "hello &lt;world&gt;", "highlightHtml empty query returns escaped text")
assert(F.highlightHtml("hello world", "world") === "hello <b>world</b>", "highlightHtml normal word")
assert(F.highlightHtml("a & b", "&") === "a <b>&amp;</b> b", "highlightHtml query containing &")
assert(F.highlightHtml("1 < 2", "<") === "1 <b>&lt;</b> 2", "highlightHtml query containing <")
assert(F.highlightHtml("cost & profit", "amp") === "cost &amp; profit", "highlightHtml 'amp' does not match inside &amp;")
assert(F.highlightHtml("a < b", "lt") === "a &lt; b", "highlightHtml 'lt' does not match inside &lt;")
assert(F.highlightHtml("meetings are toxic", "toxic meetings") === "<b>meetings</b> are <b>toxic</b>", "highlightHtml multi-word")
assert(F.highlightHtml("Hello World", "hello") === "<b>Hello</b> World", "highlightHtml case-insensitive")

// highlightHtml regex cache is bounded: more than 64 distinct queries clear the
// cache instead of growing it without bound.
for (let i = 0; i < 100; i++) F.highlightHtml("probe", "q" + i)
assert(Object.keys(F._highlightPatternCache).length <= 64, "highlightHtml cache bounded")

console.log("test_format.js: all assertions passed")
