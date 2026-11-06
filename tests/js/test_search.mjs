// js/search.mjs: index, matching, typos, close matches, suggestions, trending, draws, refreshing stored entries.
import assert from "node:assert/strict"
import * as S from "../../js/search.mjs"
import { contentKey, ENTRY_FIELDS } from "../../js/entries.mjs"

const ENTRIES = [
  { id: "a1", text: "Meetings are toxic. Remote work thrives on deep work.", type: "post", source: "https://x.com/dhh/status/1", date: "2020-03-26" },
  { id: "b2", text: "Constraints liberate even the most able minds.", type: "quote", source: "https://rubyonrails.org/doctrine" },
  { id: "c3", text: "The secret to productivity is finding the strength to do less.", type: "quote", source: "https://signalvnoise.com/posts/2106" },
  { id: "d4", text: "Yes, exactly.", type: "post", source: "https://x.com/dhh/status/9", kind: "reply", context: { author: "Jane Doe", handle: "@janedoe", text: "Original post body here." } },
  { id: "e5", text: "Worth reading again.", type: "post", source: "https://x.com/dhh/status/10", kind: "repost", context: { author: "John Smith", handle: "@johnsmith" } }
]
const ENTRIES_JSON = JSON.stringify(ENTRIES)

// A term's trend count in an index (0 when it cannot trend or is not indexed).
function trendCount(index, term) {
  const id = index.postings.termId[term]
  return id === undefined ? 0 : index.postings.trendCounts[id]
}
// The trending terms of an index, as the worker asks for them.
const trending = (index, max) => S.topTerms(index.postings.termById, index.postings.trendCounts, max)

// caseMask / applyCaseMask round-trip; unmaskable inputs return null.
const MIXED = "The Quick Brown Fox, Jumps 123!"
const maskOf = text => S.caseMask(text, text.toLowerCase())
assert(S.applyCaseMask(MIXED.toLowerCase(), maskOf(MIXED)) === MIXED, "applyCaseMask mixed-case round-trip")
assert(S.applyCaseMask("café con Ñoño", maskOf("Café con Ñoño")) === "Café con Ñoño", "applyCaseMask accented round-trip")
assert(S.applyCaseMask("great idea 💡", maskOf("Great idea 💡")) === "Great idea 💡", "applyCaseMask emoji round-trip")
assert(maskOf("İstanbul") === null, "caseMask null when lowercasing changes length")
assert(S.applyCaseMask("istanbul", null) === "istanbul", "applyCaseMask null mask passthrough")

// buildIndex: one doc per entry, sorted unique terms, stopword-free counts,
// and the caller's entries left untouched.
const index = S.buildIndex(ENTRIES)
assert(JSON.stringify(ENTRIES) === ENTRIES_JSON, "buildIndex leaves the entries it indexes untouched")
assert(index.docs.length === 5, "buildIndex one doc per entry")
assert.deepEqual(index.postings.terms.slice(0, 4), ["able", "again", "are", "body"], "buildIndex terms: sorted (quoted text included)")
const suggestable = index.postings.terms.filter(t => S.suggestWords(index, t, 1)[0] === t)
assert(suggestable.length > 20 && suggestable.every(w => S.search(index, w + " ", 40).total > 0), "suggestWords: every suggestion has results")
assert(trendCount(index, "work") === 2 && trendCount(index, "the") === 0 && index.postings.termId.the !== undefined, "buildIndex counts words, skips stopwords")
assert.deepEqual(index.postings.termById.slice().sort(), index.postings.terms, "buildIndex: termById holds the terms")
assert(index.postings.terms.every(t => index.postings.termById[index.postings.termId[t]] === t), "buildIndex: termId and termById agree")

// search: whole-word match, case restored, the ENTRY_FIELDS shape.
let found = S.search(index, "TOXIC ", 40)
assert(found.total === 1 && !found.capped && !found.closeMatches, "search single match")
assert(found.results[0].text === "Meetings are toxic. Remote work thrives on deep work.", "search restores original case")
assert.deepEqual(Object.keys(found.results[0]), ENTRY_FIELDS, "search result is in the ENTRY_FIELDS shape")

assert(S.search(index, "deep work", 40).total === 1, "search phrase match")
assert(S.search(index, "work remote", 40).total === 1, "search every word, any order")
assert(S.search(index, "janedoe", 40).results[0].id === "d4", "search matches the context handle")
assert(S.search(index, "jane doe", 40).results[0].id === "d4", "search matches the context author")

// Whole words only, and URLs are never searched: the reported bug, where
// "ruby on rails" listed Doctrine quotes because of their rubyonrails.org source.
assert(S.search(index, "rubyonrails", 40).total === 0, "search never matches the source URL")
assert(S.search(index, "doctrine", 40).total === 0, "search never matches source URL words")
assert(S.search(index, "train ", 40).total === 0, "search: a closed word never matches inside another (constraints)")
assert(S.search(index, "e", 40).total === 0, "search: a single letter matches whole tokens only")

// The last word matches as a prefix while it is being typed, not once closed.
assert(S.search(index, "medi", 40).total === 0, "search: prefix needs a real completion")
assert(S.search(index, "thriv", 40).results[0].id === "a1", "search: open last word is a prefix")
assert(S.search(index, "thriv ", 40).total === 0, "search: closed last word is exact")
// Singular/plural conflation.
assert(S.search(index, "meeting ", 40).results[0].id === "a1", "search: singular finds plural")
assert(S.search(index, "minds ", 40).results[0].id === "b2" && S.search(index, "mind ", 40).results[0].id === "b2", "search: plural and singular both match")

// -ing/-ed forms match in both directions, below the word itself (the forms
// themselves are pinned in test_words.mjs).
const inflected = S.buildIndex([
  { id: "i1", text: "Hotwire is the answer.", type: "post" },
  { id: "i2", text: "Hotwiring Rails expresses the desire.", type: "post" },
  { id: "i3", text: "Shipping this week.", type: "post" },
  { id: "i4", text: "We shipped it.", type: "post" },
])
found = S.search(inflected, "hotwire ", 40)
assert(found.total === 2 && found.results[0].id === "i1" && found.results[1].id === "i2", "search: base finds the -ing form, ranked below the exact word")
found = S.search(inflected, "hotwiring ", 40)
assert(found.total === 2 && found.results[0].id === "i2", "search: -ing form finds the base")
assert(S.search(inflected, "ship ", 40).total === 2, "search: ship finds shipping and shipped")
assert(S.search(inflected, "shipping ", 40).results.map(e => e.id).join() === "i3,i4", "search: shipping finds shipped")
assert(S.search(inflected, "ships ", 40).total === 2, "search: a plural reaches the -ing/-ed forms of its singular")
const nouns = S.buildIndex([{ id: "e1", text: "Even so, it works.", type: "post" }, { id: "e2", text: "Good evening everyone.", type: "post" }])
assert(S.search(nouns, "evening ", 40).total === 1 && S.search(nouns, "even ", 40).total === 1, "search: evening is not even")

// Close matches: nothing has every word, so posts missing one are returned
// and flagged.
found = S.search(index, "work ruby", 40)
assert(found.closeMatches && found.results[0].id === "a1", "search: close matches flagged")
found = S.search(index, "zzzz", 40)
assert(!found.closeMatches && found.total === 0, "search: one unknown word is simply no result")

// Typo correction: a word nothing matches is replaced by the most frequent
// term one edit away that keeps its first letter; `correctedQuery` is the
// query as searched, closed when its last word was corrected.
const typos = S.buildIndex([
  { id: "t1", text: "Omarchy is out. Omarchy for everyone.", type: "post" },
  { id: "t2", text: "Oligarchy themes, or anarchy.", type: "post" },
  { id: "t3", text: "A sync meeting about Omarchy.", type: "post" },
  { id: "t4", text: "Don't panic.", type: "post" },
])
found = S.search(typos, "omarcy", 40)
assert(found.correctedQuery === "omarchy " && found.total === 2 && found.results[0].id === "t1" && !found.closeMatches, "search: one-edit typo corrected to the frequent term")
assert(S.search(typos, "omarcy ", 40).correctedQuery === "omarchy ", "search: a closed typo is corrected too")
assert(S.search(typos, "oamrchy ", 40).correctedQuery === "omarchy ", "search: transposition corrected")
assert(S.search(typos, "omarchyy ", 40).correctedQuery === "omarchy ", "search: extra letter corrected")
assert(S.search(typos, "omarchi", 40).correctedQuery === "omarchy ", "search: substitution corrected")
assert(S.search(typos, "async ", 40).total === 0, "search: a correction never changes the first letter")
assert(S.search(typos, "omar", 40).total === 2 && S.search(typos, "omar", 40).correctedQuery === "", "search: a prefix being typed is not a correction")
assert(S.search(typos, "omarc", 40).correctedQuery === "", "search: an open word needs five letters to be corrected")
assert(S.search(typos, "synx ", 40).correctedQuery === "sync ", "search: a closed word needs four")
assert(S.search(typos, "syn ", 40).total === 0, "search: three letters are never corrected")
found = S.search(typos, "omarcy meeting", 40)
assert(found.correctedQuery === "omarchy meeting" && found.total === 1 && found.results[0].id === "t3", "search: a corrected earlier word leaves the open last word open")
found = S.search(typos, "don't panix", 40)
assert(found.correctedQuery === "don't panic " && found.total === 1, "search: the corrected query keeps the other words as typed")
found = S.search(typos, "omarcy zzzz yyyy", 40)
assert(found.correctedQuery === "" && found.total === 0, "search: a correction that still finds nothing is not reported")
const handles = S.buildIndex([
  { id: "h1", text: "Thanks @jasonfried for this.", type: "post" },
  { id: "h2", text: "Jason Fried wrote it.", type: "post" },
  { id: "h3", text: "Their framework, tier one.", type: "post" },
  { id: "h4", text: "I don't care.", type: "post" },
  { id: "h5", text: "Care? I don't.", type: "post" },
  { id: "h6", text: "Take care.", type: "post" },
])
assert(S.search(handles, "jasno fried ", 40).total === 2 && S.search(handles, "jason freid ", 40).total === 2, "search: joined handles are rebuilt from the corrected words")
assert(S.search(handles, "thier ", 40).total === 0, "search: a typo next to a stopword is not corrected, not even to another word")
found = S.search(handles, "thier framwork", 40)
assert(found.correctedQuery === "thier framework " && found.closeMatches && found.total === 1, "search: the other words still correct and give close matches")
// "dont" is a stopword, so "donr" is one edit from a stopword and, like
// "thier", is left uncorrected: the query gives close matches on "care".
found = S.search(handles, "donr care ", 40)
assert(found.correctedQuery === "" && found.closeMatches && found.total === 3, "search: a typo next to a contraction stopword is not corrected")
// "dont care" filters on "care" alone; the phrase bonus ranks "I don't care" first.
found = S.search(handles, "dont care ", 40)
assert(found.total === 3 && !found.closeMatches && found.results[0].id === "h4", "search: a contraction stopword does not filter; the phrase still ranks first")
assert(S.search(handles, "don't care ", 40).results[0].id === "h4", "search: the phrase matches with the apostrophe typed too")
// "shell" and "well" are words, not stopwords (their contractions are gone).
const shells = S.buildIndex([{ id: "s1", text: "A good shell.", type: "post" }, { id: "s2", text: "Oh well.", type: "post" }, { id: "s3", text: "Nothing.", type: "post" }])
assert(S.search(shells, "shell ", 40).total === 1 && S.search(shells, "well ", 40).results[0].id === "s2", "search: shell and well filter")

// Stopword-only queries still match whole words; capping and exact totals.
found = S.search(index, "the", 1)
assert(found.results.length === 1 && found.total === 2 && found.capped, "search caps at maxResults and flags it")
assert(found.results[0].id === "c3", "search: stopword query ranks posts opening with it first")
found = S.search(index, "the", 40)
assert(found.total === 2 && !found.capped, "search exact total when uncapped")
// No word characters at all: substring fallback.
assert(S.search(S.buildIndex([{ text: "東京 is great", type: "post" }]), "東京", 40).total === 1, "search: substring fallback for non-word queries")
assert.deepEqual(S.search(index, "   ", 40), { results: [], total: 0, capped: false, closeMatches: false, correctedQuery: "" }, "search blank query")
assert.deepEqual(S.search(null, "x", 40), { results: [], total: 0, capped: false, closeMatches: false, correctedQuery: "" }, "search null index")

// Ranking: the phrase in the body outranks scattered words, which outrank a
// match only in the quoted context, which outranks a passing mention.
const ranked = S.buildIndex([
  { id: "r1", text: "Somewhere in this long post about cars, racing, and food I mention ruby and rails once.", type: "post", date: "2024-01-01" },
  { id: "r2", text: "Ruby on Rails is still the fastest way to ship.", type: "post", date: "2016-01-01" },
  { id: "r3", text: "Rails, and Ruby, on the other hand.", type: "post", date: "2024-01-02" },
  { id: "r4", text: "Agreed.", type: "post", kind: "quote", date: "2025-01-01", context: { author: "Someone", handle: "@someone", text: "Ruby on Rails rocks" } }
])
found = S.search(ranked, "ruby on rails", 40)
assert(found.results[0].id === "r2", "search: the phrase in the body ranks first")
assert(found.results.map(e => e.id).indexOf("r3") < found.results.map(e => e.id).indexOf("r1"), "search: a short post about the words beats a passing mention")
assert(S.search(ranked, "ruby on ra", 40).results[0].id === "r2", "search: phrase bonus while the last word is typed")
assert(S.search(ranked, "rails", 40).total === 4, "search: total counts every whole-word match")

// Long queries: 32+ filters (a pasted paragraph) still find the post.
const longText = Array.from({ length: 40 }, (_, i) => "word" + String.fromCharCode(97 + (i % 26)) + String.fromCharCode(97 + Math.floor(i / 26))).join(" ")
const longIndex = S.buildIndex([{ id: "L", text: longText, type: "post" }, { id: "M", text: "unrelated", type: "post" }])
found = S.search(longIndex, longText + " ", 40)
assert(found.total === 1 && found.results[0].id === "L" && !found.closeMatches, "search: a 40-word pasted query finds its post exactly")
found = S.search(longIndex, Array(32).fill("wordaa").join(" ") + " ", 40)
assert(found.total === 1 && !found.closeMatches, "search: 32 repeated words are an exact match")
// The phrase bonus survives contractions and possessives, straight or curly.
const apos = S.buildIndex([
  { id: "p1", text: "Know, I said he don't well", type: "post", date: "2024-01-02" },
  { id: "p2", text: "Well I don’t know, said he", type: "post", date: "2020-01-01" },
  { id: "p3", text: "Book today: read dhh", type: "post", date: "2024-01-02" },
  { id: "p4", text: "Read dhh's book today", type: "post", date: "2020-01-01" }
])
assert(S.search(apos, "i don't know ", 40).results[0].id === "p2", "search: phrase bonus with a contraction (curly in the text)")
assert(S.search(apos, "dhh's book ", 40).results[0].id === "p4", "search: phrase bonus with a possessive")
assert(S.search(apos, "dhh book ", 40).results[0].id === "p4", "search: phrase bonus across a possessive in the text")
// Words ending in s that are not plurals are not stemmed.
const news = S.buildIndex([{ id: "n1", text: "New mood, new avatar.", type: "post" }, { id: "n2", text: "The news today.", type: "post" }])
assert(S.search(news, "news ", 40).total === 1, "search: news does not match new")
// URL fragments never trend.
assert(trendCount(S.buildIndex([{ text: "see https://example.com/https/https", type: "post" }]), "https") === 0, "buildIndex: URLs are not counted for trending")
// Trending counts the indexed body tokens: no contraction, number or token
// split off an accented word, and every counted term is searchable.
const chatter = S.buildIndex([
  { text: "Don't. I don't, you don't, they won't. I'm sure we can't.", type: "post" },
  { text: "Don’t worry about 2024 or 2024, café time.", type: "post" },
  { text: "@someone @other Can't wait for the café.", type: "post", kind: "reply", context: { author: "Some One", handle: "@someone", text: "Coffee?" } },
])
for (const t of ["dont", "wont", "im", "cant", "2024", "caf", "someone", "other"]) assert(trendCount(chatter, t) === 0, "buildIndex: " + t + " does not trend")
assert(trendCount(chatter, "café") === 2, "buildIndex: an accented word trends whole")
assert.equal(trending(chatter, 3)[0], "café", "topTerms: no contraction surfaces")

// suggestWords: sorted prefix range; multi-word, no-match and empty give
// none; single letters and pure numbers are never suggested.
assert.deepEqual(S.suggestWords(index, "re", 8), ["reading", "remote"], "suggestWords prefix matches sorted")
assert.deepEqual(S.suggestWords(index, "RE ", 8), ["reading", "remote"], "suggestWords trims and lowercases")
assert.deepEqual(S.suggestWords(index, "deep work", 8), [], "suggestWords multi-word query")
assert.deepEqual(S.suggestWords(index, "ruby", 8), [], "suggestWords no match")
assert.deepEqual(S.suggestWords(index, "", 8), [], "suggestWords empty query")
assert.deepEqual(S.suggestWords(null, "re", 8), [], "suggestWords null index")
assert.deepEqual(S.suggestWords(index, "w", 1), ["work"], "suggestWords honors max")
const numbered = S.buildIndex([{ text: "x 2024 20s 2 xbox", type: "post" }])
assert.deepEqual(S.suggestWords(numbered, "x", 8), ["xbox"], "suggestWords skips a single letter")
assert.deepEqual(S.suggestWords(numbered, "2", 8), ["20s"], "suggestWords skips pure numbers")

// prioritizeTrending: trending first in trending order, then the rest.
assert.deepEqual(S.prioritizeTrending(["a", "b", "c", "d"], ["c", "a", "z"]), ["c", "a", "b", "d"], "prioritizeTrending reorders")
assert.deepEqual(S.prioritizeTrending(["a", "b"], ["z"]), ["a", "b"], "prioritizeTrending no overlap")

// topTerms: most frequent first, ties in code-unit order, zero counts never.
assert.deepEqual(trending(index, 3), ["work", "able", "constraints"], "topTerms partial selection (again is a stopword)")
assert.deepEqual(S.topTerms(["b", "a", "c", "z"], [1, 1, 2, 0], 5), ["c", "a", "b"], "topTerms: fewer terms than max, the zero count left out")
assert.deepEqual(S.topTerms(["é", "z", "a"], [1, 1, 1], 3), ["a", "z", "é"], "topTerms: ties in code-unit order")
assert.deepEqual(S.topTerms(["a"], [1], 0), [], "topTerms: max 0")

// draw: valid entries in the ENTRY_FIELDS shape, exclusions honored, no repeats.
const one = S.draw(index, 1, [])
assert(one.length === 1 && one[0].id !== undefined && ENTRIES.some(e => e.text === one[0].text), "draw of one returns an entry, text restored")
assert.deepEqual(Object.keys(one[0]), ENTRY_FIELDS, "draw returns the ENTRY_FIELDS shape")
assert.deepEqual(S.draw(S.buildIndex([]), 1, []), [], "draw from an empty index")
assert.deepEqual(S.draw(null, 1, []), [], "draw from no index")
const excludedKeys = ["https://x.com/dhh/status/1", "https://x.com/dhh/status/9"]
for (let i = 0; i < 20; i++) {
  const entries = S.draw(index, 5, excludedKeys)
  const keys = entries.map(contentKey)
  assert(entries.length === 3, "draw returns only the non-excluded entries")
  assert(new Set(keys).size === keys.length, "draw has no repeats")
  assert(keys.every(k => !excludedKeys.includes(k)), "draw honors the exclusions")
}
assert.deepEqual(S.draw(index, 3, ENTRIES.map(e => e.source)), [], "draw with every entry excluded")

// refreshEntries: id, then source, then text; unmatched entries survive.
const refreshed = S.refreshEntries(index, [
  { id: "b2", text: "stale" },
  { source: "https://x.com/dhh/status/10", text: "stale" },
  { text: "YES, EXACTLY." },
  { text: "never indexed" },
  null
])
assert(refreshed[0].text === "Constraints liberate even the most able minds.", "refreshEntries by id")
assert(refreshed[1].id === "e5" && refreshed[1].kind === "repost", "refreshEntries by source")
assert(refreshed[2].id === "d4" && refreshed[2].text === "Yes, exactly.", "refreshEntries by case-insensitive text, case restored")
assert.deepEqual(refreshed[3], { text: "never indexed" }, "refreshEntries keeps an unmatched entry")
assert(refreshed[4] === null, "refreshEntries passes a null through")
const unindexed = [{ text: "stale" }]
assert(S.refreshEntries(null, unindexed) === unindexed, "refreshEntries without an index returns the entries as given")

console.log("test_search.mjs: all assertions passed")
