"use strict"
const path = require("path")
const vm = require("vm")

const F = require("../bin/shared").loadScript(path.join(__dirname, "..", "format.js"))

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

// formatCount
assert(F.formatCount(157) === "157", "formatCount under 1000")
assert(F.formatCount(1900) === "1.9K", "formatCount one decimal K")
assert(F.formatCount(29000) === "29K", "formatCount whole K")
assert(F.formatCount(3000000) === "3M", "formatCount whole M")
assert(F.formatCount(999) === "999", "formatCount boundary 999")
assert(F.formatCount(1000) === "1K", "formatCount boundary 1000")
assert(F.formatCount(1000000) === "1M", "formatCount boundary 1M")

// formatPosts: one decimal for K/M at any magnitude, bare under 1000
assert(F.formatPosts(157) === "157", "formatPosts under 1000")
assert(F.formatPosts(72434) === "72.4K", "formatPosts one decimal K")
assert(F.formatPosts(1900) === "1.9K", "formatPosts one decimal K low")
assert(F.formatPosts(29000) === "29K", "formatPosts whole K")
assert(F.formatPosts(1900000) === "1.9M", "formatPosts one decimal M")
assert(F.formatPosts(999) === "999", "formatPosts boundary 999")
assert(F.formatPosts(1000) === "1K", "formatPosts boundary 1000")
assert(F.formatPosts(1000000) === "1M", "formatPosts boundary 1M")

// engagementCounts: deterministic, exactly four numeric values in X-plausible ranges
const t = "determinism probe"
const c1 = F.engagementCounts(t)
const c2 = F.engagementCounts(t)
assert(c1.reply === c2.reply && c1.repost === c2.repost && c1.like === c2.like && c1.views === c2.views, "engagementCounts deterministic")
const keys = Object.keys(c1).sort()
assert(keys.length === 4 && keys[0] === "like" && keys[1] === "reply" && keys[2] === "repost" && keys[3] === "views", "engagementCounts four keys")
assert(c1.reply >= 50 && c1.reply <= 900, "engagementCounts reply in range")
assert(c1.repost >= 500 && c1.repost <= 3000, "engagementCounts repost in range")
assert(c1.like >= 2000 && c1.like <= 80000, "engagementCounts like in range")
assert(c1.views >= 100000 && c1.views <= 3000000, "engagementCounts views in range")

// engagementCounts: empty text still yields a valid hash-based set
const c0 = F.engagementCounts("")
assert(typeof c0.reply === "number" && c0.reply >= 50 && c0.reply <= 900, "engagementCounts empty text")

// _hash32: deterministic 32-bit unsigned integer (FNV-1a)
assert(F._hash32("abc") === F._hash32("abc"), "_hash32 deterministic")
assert(F._hash32("") === 2166136261, "_hash32 empty = FNV offset basis")
assert(F._hash32("a") === 3826002220, "_hash32 known value 'a'")
const h = F._hash32("abc")
assert(typeof h === "number" && Number.isInteger(h) && h >= 0 && h <= 4294967295, "_hash32 32-bit unsigned")

console.log("test_format.js: all assertions passed")
