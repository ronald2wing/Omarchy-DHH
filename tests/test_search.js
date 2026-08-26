"use strict"
const path = require("path")

const S = require("./load_script").loadScript(path.join(__dirname, "..", "search.js"))

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

// contextHandleOf: string handle passes through; missing handle -> ""
assert(S.contextHandleOf({ context: { handle: "@janedoe" } }) === "@janedoe", "contextHandleOf string handle")
assert(S.contextHandleOf({ context: { handle: "" } }) === "", "contextHandleOf empty handle")
assert(S.contextHandleOf({ context: {} }) === "", "contextHandleOf missing handle")
assert(S.contextHandleOf({}) === "", "contextHandleOf missing context")
assert(S.contextHandleOf(null) === "", "contextHandleOf null entry")
assert(S.contextHandleOf(undefined) === "", "contextHandleOf undefined entry")
// contextHandleOf: non-string handle is coerced to a string
assert(S.contextHandleOf({ context: { handle: 42 } }) === "42", "contextHandleOf numeric handle coerced")

// contextAvatarUrl: strips a leading '@' and builds the unavatar.io URL; "" for
// a missing handle.
assert(S.contextAvatarUrl("@janedoe") === "https://unavatar.io/x/janedoe", "contextAvatarUrl strips leading @")
assert(S.contextAvatarUrl("janedoe") === "https://unavatar.io/x/janedoe", "contextAvatarUrl bare handle")
assert(S.contextAvatarUrl("") === "", "contextAvatarUrl empty string")
assert(S.contextAvatarUrl(null) === "", "contextAvatarUrl null")
assert(S.contextAvatarUrl(undefined) === "", "contextAvatarUrl undefined")
// contextAvatarUrl: non-string handle is coerced to a string
assert(S.contextAvatarUrl(42) === "https://unavatar.io/x/42", "contextAvatarUrl numeric handle coerced")
// contextAvatarUrl: percent-encodes the handle (parity with the Ruby renderer's
// URI.encode_uri_component).
assert(S.contextAvatarUrl("a b") === "https://unavatar.io/x/a%20b", "contextAvatarUrl percent-encodes space")
assert(S.contextAvatarUrl("@a b") === "https://unavatar.io/x/a%20b", "contextAvatarUrl strips @ before encoding")

// fileUrlToPath: decodes valid escapes; a malformed '%-escape' falls back to the
// undecoded path (never null/throws), since the result is only used for local
// file access.
assert(S.fileUrlToPath("file:///tmp/a%20b") === "/tmp/a b", "fileUrlToPath decodes valid escape")
assert(S.fileUrlToPath("file:///tmp/a%b") === "/tmp/a%b", "fileUrlToPath keeps undecoded path on malformed escape")
assert(S.fileUrlToPath("file:///tmp/50%") === "/tmp/50%", "fileUrlToPath keeps trailing % undecoded")
assert(S.fileUrlToPath("/tmp/plain") === "/tmp/plain", "fileUrlToPath passes through scheme-less input")

// restoreCase / caseMaskFor: original case is reconstructed from the lowered
// string plus the mask, exactly, by construction; unmaskable inputs fall back
// to retaining the original text (caseMaskFor returns null).
const MIXED = "The Quick Brown Fox, Jumps 123!"
assert(S.restoreCase(MIXED.toLowerCase(), S.caseMaskFor(MIXED)) === MIXED, "restoreCase mixed-case ASCII round-trip")
assert(S.restoreCase("all lowercase already", S.caseMaskFor("all lowercase already")) === "all lowercase already", "restoreCase all-lowercase round-trip (no bits set)")
assert(S.restoreCase("café con Ñoño", S.caseMaskFor("Café con Ñoño")) === "Café con Ñoño", "restoreCase accented round-trip")
assert(S.restoreCase("great idea \uD83D\uDCA1", S.caseMaskFor("Great idea \uD83D\uDCA1")) === "Great idea \uD83D\uDCA1", "restoreCase emoji round-trip (surrogate pair untouched)")
assert(S.caseMaskFor("İstanbul") === null, "caseMaskFor null when lowercasing changes length (İ)")
assert(S.caseMaskFor("Straße") !== null && S.restoreCase("straße", S.caseMaskFor("Straße")) === "Straße", "restoreCase keeps ß (identical in both cases)")
assert(S.restoreCase("istanbul", null) === "istanbul", "restoreCase null mask returns lower unchanged")

// Build precomputed data the way SearchWorker.init does so the vocabulary
// lookup can be exercised directly.
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
  var words = S._splitWords(lowerEntries[i].t)
  for (var j = 0; j < words.length; j++) {
    if (words[j] && words[j].length >= 2) wordSet[words[j]] = true
  }
}
var lowerVocab = Object.keys(wordSet).sort()

// suggestWordsFast: prefix matches are sorted; a multi-word query (where a
// last-word-only prefix would wrongly match) and a non-matching query return
// nothing; an empty query returns nothing.
assert(S.suggestWordsFast(lowerVocab, "re").join() === "reading,remote", "suggestWordsFast prefix matches sorted")
assert(S.suggestWordsFast(lowerVocab, "deep work").length === 0, "suggestWordsFast multi-word query returns none")
assert(S.suggestWordsFast(lowerVocab, "ruby").length === 0, "suggestWordsFast no match returns none")
assert(S.suggestWordsFast(lowerVocab, "").length === 0, "suggestWordsFast empty query returns none")

console.log("test_search.js: all assertions passed")
