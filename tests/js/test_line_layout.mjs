// js/line-layout.mjs: Chirp widths, x.com's line breaks and the HTML runs.
import assert from "node:assert/strict"
import fs from "node:fs"
import * as L from "../../js/line-layout.mjs"

// Whole-line widths from x.com's own layout, written by dev/generate-chirp-metrics.mjs.
const checkLines = JSON.parse(fs.readFileSync(new URL("./chirp-check-lines.json", import.meta.url), "utf8"))

const fallback = () => 8
const text = (t, bold = false) => [{ text: t, bold }]
const lineTexts = lines => lines.map(l => l.segments.map(s => s.text).join(""))
// Chirp's width of a text on one unbounded line.
const width = (t, bold = false) => L.layoutLines(text(t, bold), Infinity, fallback)[0].width
// The metrics are stored to 0.001px a character, so whole lines agree to 0.02px.
const near = (a, b, what) => assert(Math.abs(a - b) < 0.02, what + ": " + a + " vs " + b)

// Widths agree with what x.com's own layout gave the same lines.
assert(Object.keys(checkLines).length > 0, "the check lines are there")
for (const [line, expected] of Object.entries(checkLines)) {
  near(width(line), expected, "x.com width of " + JSON.stringify(line))
}

// The timeline breaks of the full-circle post (518px column): "Linux" fits
// line 1 (512.45px), the emoji fits line 2.
const post = "It really is full circle that the man partly responsible for bringing me to Linux is now spearheading automated QA for Omarchy. Love this man! \u{1F4AA}"
assert.deepEqual(lineTexts(L.layoutLines(text(post), 518, fallback)), [
  "It really is full circle that the man partly responsible for bringing me to Linux",
  "is now spearheading automated QA for Omarchy. Love this man! \u{1F4AA}",
])
// On x.com's search page the match is bold, and "Linux" no longer fits.
const highlighted = [{ text: "It really is full circle that the man partly responsible for", bold: true }, { text: post.slice(60), bold: false }]
assert.equal(lineTexts(L.layoutLines(highlighted, 518, fallback))[0], "It really is full circle that the man partly responsible for bringing me to")
// The post page's 17px text in its 566px column is 15px text in 566*15/17.
assert.equal(L.layoutLines(text(post), 566 * 15 / 17, fallback).length, 3)

// Line breaks and blank lines are kept; spaces at a wrap hang and drop.
assert.deepEqual(lineTexts(L.layoutLines(text("one\n\ntwo"), 518, fallback)), ["one", "", "two"])
assert.deepEqual(lineTexts(L.layoutLines(text("aaaa bbbb"), 40, fallback)), ["aaaa", "bbbb"])
// Leading spaces of a paragraph show.
assert.deepEqual(lineTexts(L.layoutLines(text("  indented"), 518, fallback)), ["  indented"])
// A line's width leaves out its hanging spaces.
const [first] = L.layoutLines(text("aaaa    bbbb"), 40, fallback)
near(first.width, width("aaaa"), "hanging spaces are not counted")

// Break opportunities: after a hyphen between word characters, not after "/".
assert.deepEqual(lineTexts(L.layoutLines(text("AVX-512"), 45, fallback)), ["AVX-", "512"])
assert.equal(lineTexts(L.layoutLines(text("see https://x.com/i/broadcasts/1Nx"), 230, fallback))[1], "https://x.com/i/broadcasts/1Nx")
// A word wider than the line breaks between characters.
assert(L.layoutLines(text("a".repeat(200)), 100, fallback).every(l => l.width <= 100 + 0.01))
// Ideographs break anywhere and use the fallback width.
assert.equal(L.layoutLines(text("\u4E00".repeat(10)), 40, fallback).length, 2)

// Emoji take x.com's 20.25px.
near(width("\u{1F4AA}\u{1F3FD}"), 20.25, "emoji advance")

// HTML runs: entities decode, <b> marks bold.
assert.deepEqual(L.htmlRuns("a &amp; <b>b&lt;c</b> &#39;d&quot;"), [
  { text: "a & ", bold: false }, { text: "b<c", bold: true }, { text: " 'd\"", bold: false },
])
assert.deepEqual(L.htmlRuns(""), [])

console.log("test_line_layout.mjs: all assertions passed")
