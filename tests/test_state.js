"use strict"
const path = require("path")

const St = require("./load_script").loadScript(path.join(__dirname, "..", "state.js"))

function assert(cond, msg) {
  if (!cond) throw new Error("FAIL: " + msg)
}

// parseJsonArray: a valid JSON array round-trips; anything else (bad JSON, a
// non-array value, missing input) yields null, so callers keep their fallback.
assert(JSON.stringify(St.parseJsonArray("[1,2,3]")) === "[1,2,3]", "parseJsonArray valid array")
assert(St.parseJsonArray("[]").length === 0, "parseJsonArray empty array")
assert(JSON.stringify(St.parseJsonArray('  ["a"] ')) === '["a"]', "parseJsonArray tolerates surrounding whitespace")
assert(St.parseJsonArray("") === null, "parseJsonArray empty string null")
assert(St.parseJsonArray("not json") === null, "parseJsonArray malformed null")
assert(St.parseJsonArray('{"a":1}') === null, "parseJsonArray object null (non-array)")
assert(St.parseJsonArray("null") === null, "parseJsonArray JSON null null")
assert(St.parseJsonArray(null) === null, "parseJsonArray null input null")
assert(St.parseJsonArray(undefined) === null, "parseJsonArray undefined input null")

// recentSearchesExcluding: drop the case-insensitive (trimmed) match, keep the
// rest, and never mutate the caller's list.
const recents = ["Alpha", "beta", "gamma"]
const excl = St.recentSearchesExcluding(recents, "  ALPHA  ")
assert(excl.length === 2 && excl[0] === "beta" && excl[1] === "gamma", "recentSearchesExcluding removes case-insensitive trimmed match")
assert(recents.length === 3, "recentSearchesExcluding does not mutate input")
assert(St.recentSearchesExcluding(recents, "missing").length === 3, "recentSearchesExcluding no match keeps all")
assert(St.recentSearchesExcluding(recents, "").length === 3, "recentSearchesExcluding empty query keeps non-empty entries")
assert(St.recentSearchesExcluding([], "x").length === 0, "recentSearchesExcluding empty list")
assert(St.recentSearchesExcluding(null, "x").length === 0, "recentSearchesExcluding null list")

// buildDatasetLookup: index a JSON Lines payload by id/source/text, skipping
// blank and malformed lines and non-object values.
const LINES = [
  '{"id":"1","source":"https://x.com/dhh/status/1","text":"one"}',
  "",
  "   ",
  "{not json",
  "42",
  '{"id":"2","source":"https://x.com/dhh/status/2","text":"two"}'
].join("\n")
const lookup = St.buildDatasetLookup(LINES)
assert(lookup.byId["1"].text === "one", "buildDatasetLookup byId first")
assert(lookup.byId["2"].text === "two", "buildDatasetLookup byId second")
assert(lookup.bySource["https://x.com/dhh/status/1"].id === "1", "buildDatasetLookup bySource")
assert(lookup.byText["two"].id === "2", "buildDatasetLookup byText")
assert(lookup.byId["missing"] === undefined, "buildDatasetLookup absent id undefined")

// Empty / missing dataset still yields the three (empty) maps.
const empty = St.buildDatasetLookup("")
assert(typeof empty.byId === "object" && Object.keys(empty.byId).length === 0, "buildDatasetLookup empty raw byId")
assert(Object.keys(empty.bySource).length === 0 && Object.keys(empty.byText).length === 0, "buildDatasetLookup empty raw bySource/byText")
assert(Object.keys(St.buildDatasetLookup(null).byId).length === 0, "buildDatasetLookup null raw")

// resolveEntry: match priority id -> source -> text; the live entry wins over
// the stored snapshot, and a stored snapshot with no match is returned as-is.
const live = { id: "1", source: "https://x.com/dhh/status/1", text: "one", context: { verified: true } }
const store = St.buildDatasetLookup('{"id":"1","source":"https://x.com/dhh/status/1","text":"one"}')

// A stored snapshot whose id matches resolves via id even when source/text match others.
const byIdSource = St.buildDatasetLookup([
  '{"id":"1","source":"https://x.com/a","text":"a"}',
  '{"id":"2","source":"https://x.com/b","text":"b"}',
  '{"id":"3","source":"https://x.com/c","text":"c"}'
].join("\n"))
assert(St.resolveEntry({ id: "1", source: "https://x.com/c", text: "c" }, byIdSource).id === "1", "resolveEntry id wins")
assert(St.resolveEntry({ id: "nope", source: "https://x.com/b", text: "c" }, byIdSource).id === "2", "resolveEntry falls back to source")
assert(St.resolveEntry({ id: "nope", source: "nope", text: "c" }, byIdSource).id === "3", "resolveEntry falls back to text")
assert(St.resolveEntry({ id: "nope", source: "nope", text: "nope" }, byIdSource).id === "nope", "resolveEntry no match returns stored snapshot")
assert(St.resolveEntry(live, store) === store.byId["1"], "resolveEntry returns the live dataset object by id")
const withContext = St.buildDatasetLookup('{"id":"1","source":"https://x.com/dhh/status/1","text":"one","context":{"verified":true}}')
assert(St.resolveEntry({ id: "1", text: "one" }, withContext).context.verified === true, "resolveEntry resolves live context fields")

// resolveEntry: non-object snapshots pass through untouched.
assert(St.resolveEntry(null, store) === null, "resolveEntry null")
assert(St.resolveEntry(undefined, store) === undefined, "resolveEntry undefined")
assert(St.resolveEntry("raw", store) === "raw", "resolveEntry primitive passthrough")

console.log("test_state.js: all assertions passed")
