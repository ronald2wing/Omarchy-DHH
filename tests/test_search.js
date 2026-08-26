"use strict"
const path = require("path")

const S = require("../bin/shared").loadScript(path.join(__dirname, "..", "search.js"))

const FIXTURE = [
  { text: "Meetings are toxic. Remote work thrives on deep work.", type: "post", source: "https://x.com/dhh/status/1", date: "2020-03-26" },
  { text: "Constraints liberate even the most able minds.", type: "quote", source: "https://rubyonrails.org/doctrine" },
  { text: "The secret to productivity is finding the strength to do less.", type: "quote", source: "https://signalvnoise.com/posts/2106" },
  { text: "Yes, exactly.", type: "post", source: "https://x.com/dhh/status/9", kind: "reply", context: { author: "Jane Doe", handle: "@janedoe", text: "Original post body here." } },
  { text: "Worth reading again.", type: "post", source: "https://x.com/dhh/status/10", kind: "repost", context: { author: "John Smith", handle: "@johnsmith" } }
]

function assert(cond, msg) {
  if (!cond) throw new Error("FAIL: " + msg)
}

// searchEntries: substring match on text
let r = S.searchEntries(FIXTURE, "remote", 40)
assert(r.results.length === 1 && r.results[0].text === FIXTURE[0].text, "single-word text match")
assert(r.results[0].id === 0, "search result carries dataset index as id")
assert(r.total === 1, "single-word text match total")

// searchEntries: phrase match (every word as substring)
r = S.searchEntries(FIXTURE, "constraints minds", 40)
assert(r.results.length === 1 && r.results[0].text === FIXTURE[1].text, "multi-word phrase match")
assert(r.total === 1, "multi-word phrase match total")

// searchEntries: match on source URL
r = S.searchEntries(FIXTURE, "signalvnoise", 40)
assert(r.results.length === 1 && r.results[0].text === FIXTURE[2].text, "source match")
assert(r.total === 1, "source match total")

// searchEntries: cap at maxResults ("the" matches the two later fixtures)
r = S.searchEntries(FIXTURE, "the", 2)
assert(r.results.length === 2, "maxResults cap")
assert(r.total === 2, "maxResults cap total")

// searchEntries: total counts matches beyond the cap ("the" matches 2, max 1)
r = S.searchEntries(FIXTURE, "the", 1)
assert(r.results.length === 1, "total-beyond-cap results capped at max")
assert(r.total === 2, "total-beyond-cap total is the full match count")

// searchEntries: empty query returns { results: [], total: 0 }
r = S.searchEntries(FIXTURE, "", 40)
assert(r.results.length === 0 && r.total === 0, "empty query returns empty results and zero total")

// searchEntries: reply matches on the original post's context.text and carries context
r = S.searchEntries(FIXTURE, "post body", 40)
assert(r.results.length === 1 && r.results[0].text === FIXTURE[3].text, "reply context.text match")
assert(r.results[0].context && r.results[0].context.handle === "@janedoe", "reply result carries context")

// searchEntries: reply matches on the original post's context.handle
r = S.searchEntries(FIXTURE, "janedoe", 40)
assert(r.results.length === 1 && r.results[0].text === FIXTURE[3].text, "reply context.handle match")

// searchEntries: repost matches on context.author even without context.text
r = S.searchEntries(FIXTURE, "john smith", 40)
assert(r.results.length === 1 && r.results[0].text === FIXTURE[4].text, "repost context.author match")

// suggestWords: prefix scan, distinct, sorted
r = S.suggestWords(FIXTURE, "co", 8)
assert(r.indexOf("constraints") !== -1, "suggest finds constraints")

// slugify
assert(S.slugify("Meetings are toxic!") === "meetings-are-toxic", "slugify basic")
assert(S.slugify("  --  ") === "", "slugify empty")

// frequentTerms: frequency ordering with stopwords dropped, limit respected
const FREQ = [
  { text: "Focus on focus. Work work work.", type: "post" },
  { text: "The secret is focus and work and shipping.", type: "post" }
]
let f = S.frequentTerms(FREQ, 3)
assert(f.length === 3, "frequentTerms caps at limit")
assert(f[0] === "work", "frequentTerms most frequent first")
assert(f[1] === "focus", "frequentTerms second most frequent")
assert(f[2] === "secret", "frequentTerms alphabetical tie-break (secret before shipping)")
assert(f.indexOf("shipping") === -1, "frequentTerms excludes beyond limit")
assert(f.indexOf("the") === -1 && f.indexOf("on") === -1 && f.indexOf("is") === -1 && f.indexOf("and") === -1, "frequentTerms drops stopwords")

// frequentTerms: limit of 2 truncates the tail
f = S.frequentTerms(FREQ, 2)
assert(f.length === 2 && f[0] === "work" && f[1] === "focus", "frequentTerms limit 2")

// frequentTerms: stopword-dominant text still yields the content word
f = S.frequentTerms([{ text: "the the the the work", type: "post" }], 3)
assert(f.length === 1 && f[0] === "work", "frequentTerms ignores stopword dominance")

// frequentTerms: deterministic alphabetical tie-break
f = S.frequentTerms([{ text: "banana apple", type: "post" }], 3)
assert(f[0] === "apple" && f[1] === "banana", "frequentTerms alphabetical tie-break")

// frequentTerms: empty input
assert(S.frequentTerms([], 3).length === 0, "frequentTerms empty input")
assert(S.frequentTerms(null, 3).length === 0, "frequentTerms null input")

// Fast-path parity: build precomputed data the way SearchWorker.init does and
// assert searchEntriesFast / suggestWordsFast match their slow counterparts.
var lowerEntries = FIXTURE.map(function(e) {
  return {
    t: String(e.text || "").toLowerCase(),
    s: String(e.source || "").toLowerCase(),
    c: S._contextText(e).toLowerCase(),
    entry: e
  }
})

var wordSet = Object.create(null)
for (var i = 0; i < lowerEntries.length; i++) {
  var words = lowerEntries[i].t.split(/[^a-z']+/)
  for (var j = 0; j < words.length; j++) {
    if (words[j] && words[j].length >= 2) wordSet[words[j]] = true
  }
}
var lowerVocab = Object.keys(wordSet).sort()

// searchEntriesFast parity: same total and same first result as searchEntries.
var parityQueries = ["remote", "constraints minds", "signalvnoise", "the", "post body", "janedoe", "john smith", "deep work"]
for (var qi = 0; qi < parityQueries.length; qi++) {
  var q = parityQueries[qi]
  var slow = S.searchEntries(FIXTURE, q, 40)
  var fast = S.searchEntriesFast(lowerEntries, q, 40)
  assert(slow.total === fast.total, "searchEntriesFast total matches for '" + q + "'")
  if (slow.results.length > 0 && fast.results.length > 0) {
    assert(slow.results[0].text === fast.results[0].text, "searchEntriesFast first result matches for '" + q + "'")
  }
  assert(fast.results.length <= 40, "searchEntriesFast capped at 40 for '" + q + "'")
}

// suggestWordsFast parity: full-query prefix matches suggestWords, including the
// multi-word case (where a last-word-only prefix would wrongly return "work").
var suggestionQueries = ["re", "deep work", "ruby"]
for (var sq = 0; sq < suggestionQueries.length; sq++) {
  var sqq = suggestionQueries[sq]
  assert(S.suggestWords(FIXTURE, sqq).join() === S.suggestWordsFast(lowerVocab, sqq).join(), "suggestWordsFast matches suggestWords for '" + sqq + "'")
}

console.log("test_search.js: all assertions passed")
