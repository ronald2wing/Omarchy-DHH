// js/words.mjs: tokenizer, stopwords, stems, inflected forms, phrase RegExp and parseQuery.
import assert from "node:assert/strict"
import * as W from "../../js/words.mjs"

// rawTokens keeps the text as written; normalizeToken and tokenize lowercase,
// read ’ as ', drop a possessive 's and remove any other apostrophe.
assert.deepEqual(W.rawTokens("Don’t stop DHH's café, see https://x.com"), ["Don’t", "stop", "DHH's", "café", "see", "https", "x", "com"], "rawTokens as written")
assert.deepEqual(W.rawTokens(""), [], "rawTokens empty")
assert.deepEqual(W.rawTokens(null), [], "rawTokens null")
assert(W.normalizeToken("Don’t") === "dont" && W.normalizeToken("DHH's") === "dhh" && W.normalizeToken("Rails") === "rails", "normalizeToken")
assert(W.normalizeToken("'em") === "'em", "normalizeToken leaves a leading apostrophe alone")
assert.deepEqual(W.tokenize("I don't care about DHH’s 2 cafés"), ["i", "dont", "care", "about", "dhh", "2", "cafés"], "tokenize")
assert.deepEqual(W.tokenize("東京 💡"), [], "tokenize: no word characters, no tokens")

// Stopwords are stored tokenized: no apostrophes anywhere.
assert(W.STOPWORDS.every(w => !/['’]/.test(w)), "STOPWORDS hold tokenized forms only")
assert(new Set(W.STOPWORDS).size === W.STOPWORDS.length, "STOPWORDS has no duplicates")
// The 23 contractions whose apostrophe-free spelling is not a word.
const CONTRACTIONS = ["arent", "cant", "couldnt", "didnt", "doesnt", "dont", "hadnt", "hasnt", "havent", "isnt", "mustnt", "shant",
  "shouldnt", "wasnt", "werent", "wont", "wouldnt", "im", "ive", "youre", "youve", "theyre", "theyve"]
for (const w of CONTRACTIONS) {
  assert(W.isStopword(w), "isStopword: " + w)
  assert(W.STOPWORDS.includes(w), "STOPWORDS lists " + w)
}
// The forms that are ordinary words once the apostrophe is gone stay searchable.
for (const w of ["shell", "well", "hell", "ill", "lets", "shed", "wed", "hes", "shes"]) assert(!W.isStopword(w), "not a stopword: " + w)
// "its" and "were" are base entries; a few more base entries for good measure.
for (const w of ["its", "were", "the", "and", "a", "i", "yourselves"]) assert(W.isStopword(w), "isStopword: " + w)
// The table is prototype-less: inherited names are not stopwords.
for (const w of ["constructor", "__proto__", "toString", "hasOwnProperty", ""]) assert(!W.isStopword(w), "not a stopword: " + JSON.stringify(w))
assert(W.STOPWORDS.length === 148, "STOPWORDS: 125 base entries plus the 23 contractions")

// isContraction / isNonPlural read their tables, prototype-less.
assert(W.isContraction("dont") && W.isContraction("theyve") && !W.isContraction("its") && !W.isContraction("constructor"), "isContraction")
assert(W.isNonPlural("news") && W.isNonPlural("rails") && !W.isNonPlural("meetings") && !W.isNonPlural("toString"), "isNonPlural")
// tableOf: true for each listed string, nothing inherited.
const table = W.tableOf(["a", "b"])
assert(table.a === true && table.b === true && table.c === undefined && table.toString === undefined, "tableOf")

// pluralStem: plural-only conflation; listed words ending in s are kept.
assert(W.pluralStem("news") === "news" && W.pluralStem("series") === "series" && W.pluralStem("meetings") === "meeting", "pluralStem keeps non-plurals")
const stems = { meetings: "meeting", taxes: "tax", companies: "company", boss: "boss", bus: "bus", status: "status", rails: "rails",
  classes: "class", watches: "watch", boxes: "box", ties: "tie", is: "is", racing: "racing" }
for (const [word, stem] of Object.entries(stems)) assert(W.pluralStem(word) === stem, "pluralStem " + word)

// inflectedForms: both directions, doubling, listed non-inflections. Only
// the meaningful forms are pinned: the generator also offers candidates that
// are no words ("shiping"), which search drops unless the index holds them.
function forms(word, included, excluded) {
  const f = W.inflectedForms(word)
  for (const w of included) assert(f.includes(w), "inflectedForms(" + word + ") includes " + w)
  for (const w of excluded) assert(!f.includes(w), "inflectedForms(" + word + ") leaves out " + w)
}
assert.deepEqual(W.inflectedForms("hotwire"), ["hotwiring", "hotwired"], "inflectedForms: base to -ing/-ed, e dropped")
forms("ship", ["shipping", "shipped"], ["ship"])
forms("racing", ["race", "raced"], ["racing", "racinged"])
forms("shipped", ["ship", "shipping"], ["shipped"])
forms("tried", ["try", "trying"], ["tried"])
forms("thing", [], ["th", "thin"])
assert.deepEqual(W.inflectedForms("evening"), [], "inflectedForms: a listed non-inflection is kept whole")
assert(W.inflectedForms("even").indexOf("evening") === -1 && W.inflectedForms("rug").indexOf("rugged") === -1, "inflectedForms: listed words are never generated either")

// escapeRegex, the RegExp sources, phraseSource and phraseRegExp.
assert(W.escapeRegex("a.b*c(d)[e]") === "a\\.b\\*c\\(d\\)\\[e\\]", "escapeRegex")
assert(new RegExp("^" + W.NON_WORD + "$").test("-") && !new RegExp("^" + W.NON_WORD + "$", "i").test("É"), "NON_WORD")
assert(new RegExp("ab" + W.WORD_END).test("ab.") && !new RegExp("ab" + W.WORD_END).test("abc"), "WORD_END")
assert(new RegExp("^" + W.phraseSource(["ruby", "rails"]) + "$").test("ruby -- rails"), "phraseSource joins words across non-word runs")
let re = W.phraseRegExp(["dont", "care"], false, false)
assert(re.test("i don't care.") && re.test("i don’t care") && re.test("dont care") && !re.test("i don't careful"), "phraseRegExp across an apostrophe the query lacks, closed")
assert(!re.global, "phraseRegExp without capture only tests")
re = W.phraseRegExp(["dhh", "book"], true, false)
assert(re.test("read dhh's book") && re.test("dhh bookmarks"), "phraseRegExp across a possessive, open last word")
assert(!W.phraseRegExp(["f", "latte"], false, false).test("café latte"), "phraseRegExp never starts inside an accented word")
re = W.phraseRegExp(["i", "don't", "know"], false, true)
const m = re.exec("well i don’t know")
assert(re.global && m && m[1] === " " && m[2] === "i don’t know", "phraseRegExp with capture: boundary and phrase groups")

// parseQuery: the shape search and highlighting both read.
let p = W.parseQuery("dont care ")
assert.deepEqual(p, { rawWords: ["dont", "care"], words: ["dont", "care"], lastWordOpen: false, dangling: false, scoredCount: 2,
  allStopwords: false, filters: [{ word: "care", wordIndex: 1, stem: "care", forms: ["caring", "cared"], exactOnly: false, prefix: false }],
  joined: ["dontcare"] }, "parseQuery: a contraction stopword does not filter, but still joins")
p = W.parseQuery("Ruby on r")
assert(p.lastWordOpen && p.dangling && !p.allStopwords && p.scoredCount === 2, "parseQuery: a one-letter open word after others dangles")
assert.deepEqual(p.filters.map(f => f.word), ["ruby"], "parseQuery: the dangling word and the stopword do not filter")
assert.deepEqual(p.joined, ["rubyon"], "parseQuery: joined pairs stop before the dangling word")
p = W.parseQuery("the")
assert(p.allStopwords && p.lastWordOpen && p.filters.length === 1 && p.filters[0].exactOnly && p.filters[0].stem === null && p.filters[0].forms.length === 0 && !p.filters[0].prefix,
  "parseQuery: an all-stopword query matches its words exactly")
assert.deepEqual(p.joined, [], "parseQuery: an all-stopword query joins nothing")
p = W.parseQuery("then don’t ")
assert(!p.allStopwords && p.filters.length === 1 && p.filters[0].word === "dont" && !p.filters[0].exactOnly,
  "parseQuery: stopwords and a contraction filter on the contraction, as an ordinary word")
assert.deepEqual(p.joined, ["thendont"], "parseQuery: a contraction query still joins")
p = W.parseQuery("im")
assert(!p.allStopwords && p.filters.length === 1 && p.filters[0].prefix, "parseQuery: a lone open contraction is a prefix (\"im\" on the way to \"image\")")
p = W.parseQuery("Omarch")
assert(p.filters.length === 1 && p.filters[0].prefix && p.filters[0].word === "omarch", "parseQuery: the open last word is a prefix")
assert(!W.parseQuery("omarch ").filters[0].prefix && !W.parseQuery("omarch.").filters[0].prefix, "parseQuery: whitespace or punctuation closes the word")
p = W.parseQuery("ships ")
assert(p.filters[0].stem === "ship" && p.filters[0].forms.includes("shipping") && p.filters[0].forms.includes("shipped"), "parseQuery: forms of the word and of its singular")
p = W.parseQuery("I DON’T know")
assert.deepEqual(p.rawWords, ["i", "don't", "know"], "parseQuery: raw words lowercased, ’ read as '")
assert.deepEqual(p.words, ["i", "dont", "know"], "parseQuery: words normalized")
assert.deepEqual(p.filters.map(f => [f.word, f.wordIndex]), [["know", 2]], "parseQuery: wordIndex indexes words")
p = W.parseQuery("a x ")
assert(p.filters.length === 1 && p.filters[0].word === "x" && p.filters[0].exactOnly && p.filters[0].stem === null, "parseQuery: a one-letter word is exact only")
p = W.parseQuery("   ")
assert(p.words.length === 0 && p.filters.length === 0 && p.joined.length === 0 && p.scoredCount === 0, "parseQuery: blank")
assert(W.parseQuery("💡").words.length === 0, "parseQuery: no word characters")

console.log("test_words.mjs: all assertions passed")
