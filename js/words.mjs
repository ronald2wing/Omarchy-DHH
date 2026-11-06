// The word layer search and highlighting share: tokens, stopwords, stems, inflected forms, parseQuery.

// Characters that form words: ASCII letters and digits plus Latin accents,
// as the inside of a RegExp character class (match it case-insensitively).
export const WORD_CHARS = "a-z0-9À-ɏ"

// RegExp sources: one character that is not a word character, and the end of
// a word (no word character follows).
export const NON_WORD = "[^" + WORD_CHARS + "]"
export const WORD_END = "(?![" + WORD_CHARS + "])"

// One raw word token: a run of word characters, optionally followed by one
// apostrophe (straight or curly) and letters ("don't", "dhh's"). Global and
// case-insensitive, so it runs on raw text, where highlighting needs the
// positions, as well as on lowercased text.
export const WORD_RE = new RegExp("[" + WORD_CHARS + "]+(?:['’][a-z]+)?", "gi")

// URLs are never searched, counted or highlighted.
export const URL_RE = /https?:\/\/\S+/gi

// A raw query whose last character is a word character (or an apostrophe) is
// still being typed: its last word is open and matches as a prefix.
const OPEN_END_RE = new RegExp("[" + WORD_CHARS + "'’]$")

// Contractions, in tokenized form. Only those whose apostrophe-free spelling
// is not an ordinary word are listed: "shell", "well", "hell", "ill", "lets",
// "shed", "wed", "hes" and "shes" stay searchable. "its" and "were" are base
// stopwords.
const CONTRACTIONS = [
  "arent", "cant", "couldnt", "didnt", "doesnt", "dont", "hadnt", "hasnt",
  "havent", "isnt", "mustnt", "shant", "shouldnt", "wasnt", "werent", "wont",
  "wouldnt", "im", "ive", "youre", "youve", "theyre", "theyve"
]

// Common English stopwords plus the contractions, in tokenized form
// (apostrophes removed, as normalizeToken does). They never trend, and they
// filter only in a query made of nothing else: a query of base stopwords
// alone matches them as exact words, and one holding a contraction filters
// on its contractions like ordinary words ("then don't", "im" on the way to
// "image"), see parseQuery.
export const STOPWORDS = [
  "a", "about", "above", "after", "again", "against", "all", "am", "an", "and",
  "any", "are", "as", "at", "be", "because", "been", "before", "being",
  "below", "between", "both", "but", "by", "can", "cannot", "could",
  "did", "do", "does", "doing", "down",
  "during", "each", "few", "for", "from", "further", "had", "has",
  "have", "having", "he", "her",
  "here", "hers", "herself", "him", "himself", "his", "how",
  "i", "if", "in", "into", "is", "it",
  "its", "itself", "me", "more", "most", "my",
  "myself", "no", "nor", "not", "of", "off", "on", "once", "only", "or", "other",
  "ought", "our", "ours", "ourselves", "out", "over", "own", "same",
  "she", "should", "so", "some", "such",
  "than", "that", "the", "their", "theirs", "them", "themselves",
  "then", "there", "these", "they",
  "this", "those", "through", "to", "too", "under", "until", "up",
  "very", "was", "we", "were",
  "what", "when", "where", "which",
  "while", "who", "whom", "why", "with", "would",
  "you", "your", "yours",
  "yourself", "yourselves"
].concat(CONTRACTIONS)

// Words ending in s that are not plurals (or are names), so they are never
// stemmed: "news" must not match every "new".
const NON_PLURALS = ["news", "lens", "bus", "gas", "plus", "yes", "this", "has", "was", "does", "is", "always", "perhaps",
  "chaos", "bias", "canvas", "atlas", "alias", "series", "species", "basis", "thesis", "analysis", "crisis",
  "process", "access", "success", "business", "less", "unless", "across", "status", "campus", "virus", "bonus",
  "focus", "nexus", "corpus", "apparatus", "omnibus", "versus", "previous", "famous", "serious", "various", "obvious",
  "nervous", "anonymous", "ios", "macos", "kubernetes", "postgres", "redis", "rails", "hotwire", "aws", "dhh", "us"]

// Words ending in -ing/-ed that are not inflections ("evening" is not
// "even", "rugged" is not "rug"), so they are neither split nor generated.
const NON_INFLECTED = ["evening", "morning", "nothing", "something", "anything", "everything",
  "string", "spring", "ceiling", "sibling", "darling", "sterling", "viking", "dumpling", "lightning", "shilling",
  "earring", "herring", "offspring", "pudding", "hundred", "sacred", "hatred", "kindred", "wicked", "naked",
  "crooked", "rugged", "jagged", "ragged", "wretched", "speed", "indeed", "exceed", "succeed", "proceed", "embed"]

// A prototype-less lookup table holding `true` for each string in `list`.
// Not a Set: Qt's V4 engine implements Set lookups as linear scans.
export function tableOf(list) {
  const table = Object.create(null)
  for (let i = 0; i < list.length; i++) table[list[i]] = true
  return table
}
const STOPWORD_TABLE = tableOf(STOPWORDS)
const CONTRACTION_TABLE = tableOf(CONTRACTIONS)
const NON_PLURAL_TABLE = tableOf(NON_PLURALS)
const NON_INFLECTED_TABLE = tableOf(NON_INFLECTED)

export function isStopword(token) {
  return STOPWORD_TABLE[token] === true
}

export function isContraction(token) {
  return CONTRACTION_TABLE[token] === true
}

export function isNonPlural(word) {
  return NON_PLURAL_TABLE[word] === true
}

function isNonInflected(word) {
  return NON_INFLECTED_TABLE[word] === true
}

// The raw word tokens of a text, as written (case and apostrophes kept).
export function rawTokens(text) {
  return String(text || "").match(WORD_RE) || []
}

// A raw token as the index holds it: lowercased, the curly apostrophe read as
// a straight one, a possessive 's dropped, any other apostrophe removed
// ("don't" -> "dont", "dhh's" -> "dhh").
export function normalizeToken(raw) {
  const t = String(raw).toLowerCase().replace(/’/g, "'")
  const q = t.indexOf("'")
  if (q <= 0) return t
  return t.slice(-2) === "'s" ? t.slice(0, q) : t.replace("'", "")
}

// The normalized tokens of a text.
export function tokenize(text) {
  const tokens = rawTokens(text)
  for (let i = 0; i < tokens.length; i++) tokens[i] = normalizeToken(tokens[i])
  return tokens
}

// Plural-only conflation (meeting/meetings, tax/taxes, company/companies).
// No -ing/-ed stripping on purpose: "racing" is not "race".
export function pluralStem(t) {
  if (isNonPlural(t)) return t
  const n = t.length
  if (n > 4 && t.slice(-3) === "ies") return t.slice(0, -3) + "y"
  if (n > 4 && (t.slice(-4) === "sses" || t.slice(-4) === "shes" || t.slice(-4) === "ches" || t.slice(-3) === "xes")) return t.slice(0, -2)
  if (n > 3 && t[n - 1] === "s" && t[n - 2] !== "s" && t[n - 2] !== "u" && t[n - 2] !== "i") return t.slice(0, -1)
  return t
}

// The -ing/-ed forms of a word and the bases they come from, with the final
// e restored and doubled consonants undone, so "hotwire" finds "hotwiring",
// "racing" finds "race" and "ship" finds "shipping". Pure string generation;
// search keeps the forms its index holds.
export function inflectedForms(word) {
  const w = String(word)
  const n = w.length
  // A listed word is no inflection and has none.
  if (isNonInflected(w)) return []
  const bases = [w]
  function addBase(b) { if (b.length >= 3 && bases.indexOf(b) === -1) bases.push(b) }
  // The word minus its -ing or -ed, then that with the e restored, the -ied
  // read as -y, and a doubled final consonant undone.
  const bare = n > 5 && w.slice(-3) === "ing" ? w.slice(0, -3) : n > 4 && w.slice(-2) === "ed" ? w.slice(0, -2) : null
  if (bare !== null) {
    addBase(bare)
    addBase(bare + "e")
    if (w.slice(-3) === "ied") addBase(w.slice(0, -3) + "y")
    if (bare.length > 3 && bare[bare.length - 1] === bare[bare.length - 2]) addBase(bare.slice(0, -1))
  }
  const forms = []
  // An -ing/-ed word itself only contributes its bases.
  for (let i = bases.length > 1 ? 1 : 0; i < bases.length; i++) {
    const b = bases[i]
    const last = b[b.length - 1]
    const candidates = [b]
    if (last === "e") candidates.push(b.slice(0, -1) + "ing", b.slice(0, -1) + "ed")
    else {
      candidates.push(b + "ing", b + "ed")
      if (last === "y") candidates.push(b.slice(0, -1) + "ied")
      // A final consonant after a vowel doubles ("ship" -> "shipping"); only
      // for the word itself, a derived base already undid its doubling.
      else if (i === 0 && b.length >= 2 && "aeiou".indexOf(b[b.length - 2]) >= 0 && "aeiouwxy".indexOf(last) < 0) candidates.push(b + last + "ing", b + last + "ed")
    }
    for (let k = 0; k < candidates.length; k++) {
      const c = candidates[k]
      if (c !== w && c.length >= 3 && !isNonInflected(c) && forms.indexOf(c) === -1) forms.push(c)
    }
  }
  return forms
}

// A word's variants the search also matches: its singular (`stem`) and the
// -ing/-ed forms of the word and of its singular (`forms`, "ships" finds
// "shipping"). Search keeps the variants its index holds.
export function wordVariants(word) {
  const stem = pluralStem(word)
  const forms = inflectedForms(word)
  if (stem !== word) {
    const more = inflectedForms(stem)
    for (let k = 0; k < more.length; k++) if (forms.indexOf(more[k]) === -1) forms.push(more[k])
  }
  return { stem: stem, forms: forms }
}

export function escapeRegex(s) {
  return String(s).replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
}

// A RegExp source matching `wordSources` (RegExp sources, one per word) in
// order, with a run of non-word characters between each two.
export function phraseSource(wordSources) {
  return wordSources.join(NON_WORD + "+")
}

// A RegExp matching the query's words in order as they are written in a
// lowercased text. Built from the raw query words (not the normalized
// tokens), so "don't" matches "don't"/"don’t", "dont" matches "don't" as the
// tokenizer reads it, and "dhh book" matches "dhh's book". The last word is
// left open (a prefix) when `lastWordOpen`. With `capture` the RegExp is
// global and captures the leading boundary (group 1) and the phrase itself
// (group 2), for highlighting; without, it only tests.
export function phraseRegExp(rawWords, lastWordOpen, capture) {
  const phrase = phraseSource(rawWords.map(function(w) {
    if (w.indexOf("'") >= 0 || w.indexOf("’") >= 0) return escapeRegex(w.replace(/’/g, "'")).replace(/'/g, "['’]")
    return w.split("").map(escapeRegex).join("['’]?") + "(?:['’]s)?"
  }))
  const end = lastWordOpen ? "" : WORD_END
  if (capture) return new RegExp("(^|" + NON_WORD + ")(" + phrase + ")" + end, "g")
  return new RegExp("(?:^|" + NON_WORD + ")" + phrase + end)
}

// A typed query, parsed once for both search and highlighting:
//   rawWords      the lowercased raw tokens (apostrophes kept, ’ as '), for
//                 the phrase
//   words         the normalized tokens
//   lastWordOpen  the last word is still being typed (the raw query does not
//                 end in whitespace or punctuation)
//   dangling      a one-letter word being typed after others ("ruby on r"):
//                 too short to filter on, it only steers the phrase
//   scoredCount   how many leading `words` are scored: all but a dangling one
//   allStopwords  every scored word is a base stopword; they then match as
//                 exact words
//   filters       the words that must match: the scored non-stopwords (every
//                 scored word when allStopwords; the contractions when the
//                 scored words are stopwords and contractions only), each
//                 { word, wordIndex, stem, forms, exactOnly, prefix }.
//                 `wordIndex` indexes `words`; `stem` is null and `forms`
//                 empty for an exact-only word; `forms` are the -ing/-ed forms
//                 of the word and of its singular; `prefix` is set on the open
//                 last word.
//   joined        adjacent scored word pairs written together ("jason fried"
//                 -> "jasonfried"); joined[i] joins words[i] and words[i + 1].
//                 A pair counts even when one half is a stopword ("any way" ->
//                 "anyway"); none in an all-stopword query.
export function parseQuery(raw) {
  const lower = String(raw || "").toLowerCase()
  const rawWords = rawTokens(lower.replace(/’/g, "'"))
  const words = rawWords.map(normalizeToken)
  const lastWordOpen = OPEN_END_RE.test(lower)
  const dangling = lastWordOpen && words.length > 1 && words[words.length - 1].length === 1
  const scoredCount = dangling ? words.length - 1 : words.length
  let allStopwords = true
  let anyContraction = false
  for (let i = 0; i < scoredCount; i++) {
    if (!isStopword(words[i])) allStopwords = false
    else if (isContraction(words[i])) anyContraction = true
  }
  // Stopwords and contractions only: the contractions filter, as ordinary
  // words, and the rest are skipped.
  const contractionsFilter = allStopwords && anyContraction
  if (contractionsFilter) allStopwords = false
  const filters = []
  for (let i = 0; i < scoredCount; i++) {
    const word = words[i]
    if (!allStopwords && isStopword(word) && !(contractionsFilter && isContraction(word))) continue
    const exactOnly = allStopwords || word.length < 2
    const variants = exactOnly ? { stem: null, forms: [] } : wordVariants(word)
    filters.push({ word: word, wordIndex: i, stem: variants.stem, forms: variants.forms, exactOnly: exactOnly,
                   prefix: !exactOnly && lastWordOpen && i === words.length - 1 })
  }
  const joined = []
  if (!allStopwords) for (let i = 0; i + 1 < scoredCount; i++) joined.push(words[i] + words[i + 1])
  return { rawWords: rawWords, words: words, lastWordOpen: lastWordOpen, dangling: dangling, scoredCount: scoredCount,
           allStopwords: allStopwords, filters: filters, joined: joined }
}
