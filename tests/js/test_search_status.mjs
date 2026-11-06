// js/search-status.mjs: every status-line branch, the filler flag and the highlight query.
import assert from "node:assert/strict"
import { describeResponse, LOADING_TEXT, SEARCHING_TEXT } from "../../js/search-status.mjs"

const MAX = 40
function status(response, query) { return describeResponse(response, query === undefined ? "q" : query, MAX) }
const results = n => Array.from({ length: n }, (_, i) => ({ id: "e" + i }))

// A corrected query with close matches names the correction, trimmed; the
// rows highlight it as the worker sent it.
assert.deepEqual(status({ results: results(3), total: 3, capped: false, closeMatches: true, correctedQuery: "omarchy meeting " }, "omarcy meeting"),
  { text: "Close matches for “omarchy meeting”", needsFiller: false, highlightQuery: "omarchy meeting " }, "corrected close matches")
// A corrected query names the correction and the count, capped or not.
assert.deepEqual(status({ results: results(5), total: 5, capped: false, closeMatches: false, correctedQuery: "omarchy " }, "omarcy"),
  { text: "Showing results for “omarchy” · 5", needsFiller: false, highlightQuery: "omarchy " }, "corrected results")
assert.deepEqual(status({ results: results(40), total: 709, capped: true, closeMatches: false, correctedQuery: "omarchy " }, "omarcy"),
  { text: "Showing results for “omarchy” · 40+", needsFiller: false, highlightQuery: "omarchy " }, "corrected results, capped")
// Close matches without a correction.
assert.deepEqual(status({ results: results(2), total: 2, capped: false, closeMatches: true, correctedQuery: "" }),
  { text: "No exact results · close matches", needsFiller: false, highlightQuery: "q" }, "close matches")
// Capped, then the exact count with its plural.
assert.deepEqual(status({ results: results(40), total: 52, capped: true, closeMatches: false, correctedQuery: "" }),
  { text: "40+ results", needsFiller: false, highlightQuery: "q" }, "capped")
assert.equal(status({ results: results(7), total: 7, capped: false, closeMatches: false, correctedQuery: "" }).text, "7 results", "plural count")
assert.equal(status({ results: results(1), total: 1, capped: false, closeMatches: false, correctedQuery: "" }).text, "1 result", "singular count")
// A response without a total counts its results.
assert.equal(status({ results: results(2) }).text, "2 results", "total falls back to the result count")
// Nothing matched: curly quotes around the query as typed, and the filler.
assert.deepEqual(status({ results: [], total: 0, capped: false, closeMatches: false, correctedQuery: "" }, "zzzz"),
  { text: "No results for “zzzz”", needsFiller: true, highlightQuery: "zzzz" }, "no results")
assert.deepEqual(status({}, "zzzz"), { text: "No results for “zzzz”", needsFiller: true, highlightQuery: "zzzz" }, "an empty response is no results")

// The copy shown before a response arrives.
assert.equal(LOADING_TEXT, "Loading posts…")
assert.equal(SEARCHING_TEXT, "Searching…")

console.log("test_search_status.mjs: all assertions passed")
