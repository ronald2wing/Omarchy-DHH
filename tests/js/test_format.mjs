// js/format.mjs: every export through its case table, then the clock-relative dates and the ranges.
import fs from "node:fs"
import assert from "node:assert/strict"
import * as F from "../../js/format.mjs"
import { assertCases } from "./cases.mjs"

const CASES = {
  escapeHtml: [
    { args: ["<>&\"'"], expected: "&lt;&gt;&amp;&quot;&#39;" },
    { args: ["plain text 123"], expected: "plain text 123" },
    { args: ["&amp;"], expected: "&amp;amp;" }
  ],
  unescapeHtml: [
    { args: ["&lt;&gt;&amp;&quot;&#39;"], expected: "<>&\"'" },
    { args: ["plain text 123"], expected: "plain text 123" },
    { args: ["&amp;amp;"], expected: "&amp;" },
    { args: ["&amp;lt;b&amp;gt;"], expected: "&lt;b&gt;" },
    { args: ["&nbsp; &#40; & ;"], expected: "&nbsp; &#40; & ;" }
  ],
  formatDate: [
    { args: ["2020-12-07"], expected: "Dec 7, 2020" },
    { args: [""], expected: "" },
    { args: [null], expected: "" },
    { args: ["not a date"], expected: "" },
    { args: ["2020-13-45"], expected: "" }
  ],
  hash32: [
    { args: [""], expected: 2166136261 },
    { args: ["a"], expected: 3826002220 },
    { args: ["abc"], expected: 440920332 },
    { args: ["💡"], expected: 741291884 }
  ],
  formatEngagementCount: [
    { args: [157], expected: "157" },
    { args: [999], expected: "999" },
    { args: [1000], expected: "1K" },
    { args: [1023], expected: "1K" },
    { args: [1555], expected: "1.6K" },
    { args: [1900], expected: "1.9K" },
    { args: [9999], expected: "10K" },
    { args: [10000], expected: "10K" },
    { args: [12345], expected: "12K" },
    { args: [29000], expected: "29K" },
    { args: [999999], expected: "1000K" },
    { args: [1000000], expected: "1M" },
    { args: [1500000], expected: "1.5M" },
    { args: [3000000], expected: "3M" }
  ],
  formatPostCount: [
    { args: [157], expected: "157" },
    { args: [999], expected: "999" },
    { args: [1000], expected: "1K" },
    { args: [1900], expected: "1.9K" },
    { args: [29000], expected: "29K" },
    { args: [72434], expected: "72.4K" },
    { args: [1000000], expected: "1M" },
    { args: [1900000], expected: "1.9M" }
  ],
  decorativeEngagementCounts: [
    { args: ["determinism probe"], expected: { reply: 317, repost: 618, like: 14235, views: 1350980 } },
    { args: [""], expected: { reply: 707, repost: 2039, like: 10565, views: 1567059 } }
  ],
  handleLine: [
    { args: ["@dhh", "2020-12-07"], expected: "@dhh · Dec 7, 2020" },
    { args: ["@jane_doe", ""], expected: "@jane_doe" },
    { args: ["@jane_doe", null], expected: "@jane_doe" },
    { args: ["@jane_doe", "not a date"], expected: "@jane_doe" },
    { args: ["<@a&b>", "2019-01-31"], expected: "<@a&b> · Jan 31, 2019" },
    { args: [null, "2019-01-31"], expected: " · Jan 31, 2019" }
  ],
  sealIconName: [
    { args: ["organization"], expected: "verified-gold" },
    { args: ["government"], expected: "verified-grey" },
    { args: ["individual"], expected: "verified-blue" },
    { args: [""], expected: "verified-blue" },
    { args: [null], expected: "verified-blue" }
  ]
}
assertCases(F, CASES, "format.mjs")
assert.deepEqual(Object.keys(F).sort(), Object.keys(CASES).sort(), "every format.mjs export has cases")

// escapeHtml and unescapeHtml round-trip any text.
for (const s of ["<a href=\"x\">it's & that</a>", "&amp;lt;", "plain", ""]) assert.equal(F.unescapeHtml(F.escapeHtml(s)), s, "escape round-trip: " + s)

// formatDate: undefined has no JSON form, so it stays out of the table.
assert.equal(F.formatDate(undefined), "", "formatDate undefined")

// formatDate relative to a fixed local clock, mid-July so no daylight-saving
// change falls inside the 7-day window: hours since that day's local
// midnight, then whole days, then the date.
const now = new Date(2026, 6, 15, 12, 30)
const relative = { "2026-07-15": "12h", "2026-07-14": "1d", "2026-07-12": "3d", "2026-07-09": "6d", "2026-07-08": "Jul 8",
  "2026-07-16": "Jul 16", "2026-01-02": "Jan 2", "2025-07-15": "Jul 15, 2025" }
for (const [date, expected] of Object.entries(relative)) assert.equal(F.formatDate(date, now), expected, "formatDate " + date + " at 2026-07-15 12:30")
assert.equal(F.formatDate("2026-07-15", new Date(2026, 6, 15)), "0h", "formatDate at that day's midnight")

// decorativeEngagementCounts: four values in range for any text.
for (const text of ["determinism probe", "", "another probe", "\u{1F4A1}"]) {
  const c = F.decorativeEngagementCounts(text)
  assert(Object.keys(c).sort().join() === "like,reply,repost,views", "decorativeEngagementCounts four keys: " + text)
  assert(c.reply >= 50 && c.reply <= 900 && c.repost >= 500 && c.repost <= 3000, "decorativeEngagementCounts reply/repost range: " + text)
  assert(c.like >= 2000 && c.like <= 80000 && c.views >= 100000 && c.views <= 3000000, "decorativeEngagementCounts like/views range: " + text)
}

// hash32 stays a 32-bit unsigned integer (the table pins the values).
assert(Number.isInteger(F.hash32("abc")) && F.hash32("abc") <= 4294967295, "hash32 32-bit unsigned")

// handleLine: an unparseable date leaves the handle alone (the table pins
// the rest); sealIconName names an icon that exists.
assert.equal(F.handleLine("@dhh", "2024-02-30x"), "@dhh", "handleLine drops an unparseable date")
for (const t of ["organization", "government", "individual"]) {
  assert(fs.existsSync(new URL("../../assets/icons/" + F.sealIconName(t) + ".svg", import.meta.url)), "sealIconName icon exists: " + t)
}

console.log("test_format.mjs: all assertions passed")
