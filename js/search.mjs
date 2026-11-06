// The search index: build, search, suggest, trending, draw and refresh stored entries (worker and node only).

import { toEntry, withoutReplyMentions, contentKey, isRepost, LEADING_MENTIONS } from "./entries.mjs"
import { WORD_CHARS, WORD_END, URL_RE, isStopword, tokenize, pluralStem, wordVariants, escapeRegex, phraseSource,
         phraseRegExp, parseQuery } from "./words.mjs"

// A token of digits only: never suggested and never trending.
const NUMBER_RE = /^[0-9]+$/

// Whether an indexed term may be suggested: not a single letter and not a
// pure number. Trending terms are the suggestable ones that are not
// stopwords.
function isSuggestable(t) {
  return t.length >= 2 && !NUMBER_RE.test(t)
}

// The searched fields of a doc, in the order of their 4-bit slots in a
// posting's packed term frequency.
const FIELD_BODY = 0
const FIELD_CONTEXT = 1
const FIELD_AUTHOR = 2
const FIELD_TITLE = 3
const FIELD_COUNT = 4
const FIELD_WEIGHT_CONTEXT = 0.3
const FIELD_WEIGHT_AUTHOR = 0.3
const FIELD_WEIGHT_TITLE = 0.8
const BM25_K1 = 1.0
const BM25_B_BODY = 0.5
const BM25_B_CONTEXT = 0.5
const PLURAL_WEIGHT = 0.6
const INFLECTED_WEIGHT = 0.5
// A completion of the open last word weighs COMPLETION_WEIGHT_BASE plus that
// much again times the share of the completion already typed, at most
// COMPLETION_WEIGHT_MAX, and COMPLETION_AFTER_EXACT times that when the typed
// word is a word on its own ("ai" must not rank "airpods" first).
const COMPLETION_WEIGHT_BASE = 0.45
const COMPLETION_WEIGHT_MAX = 0.85
const COMPLETION_AFTER_EXACT = 0.5
// One bit per filter in a 32-bit mask: past this many words (a pasted
// paragraph) the rest only shape the phrase bonus.
const MAX_FILTERS = 31
// Typo correction applies to a word nothing matches: a closed word of this
// length or more, or a word still being typed one letter longer (shorter
// words have too many neighbours).
const TYPO_MIN_LENGTH = 4
const TYPO_MIN_LENGTH_OPEN = 5
const ALPHABET = "abcdefghijklmnopqrstuvwxyz"
const PHRASE_BONUS_BODY = 2.0
const PHRASE_BONUS_CONTEXT = 1.15
const LEAD_BONUS = 1.25
const CURATED_PRIOR = 1.2
const RECENCY_BOOST = 0.12
const RECENCY_HALF_LIFE_YEARS = 3
const CLOSE_MATCH_FACTOR = 0.5
// Quality: a reply with a body under REPLY_SHORT_LENGTH characters (reply
// mentions removed) weighs SHORT_REPLY_QUALITY, under REPLY_MEDIUM_LENGTH
// MEDIUM_REPLY_QUALITY; a repost of someone else's words REPOST_QUALITY.
const REPLY_SHORT_LENGTH = 40
const REPLY_MEDIUM_LENGTH = 90
const SHORT_REPLY_QUALITY = 0.8
const MEDIUM_REPLY_QUALITY = 0.9
const REPOST_QUALITY = 0.8

// ---- case mask -------------------------------------------------------------
//
// The index keeps each text once, lowercased, plus a per-code-unit bitmask of
// the units that were uppercase, instead of retaining both the original and
// the lowered copy. Bit i (LSB-first per byte) is set when unit i differs
// between original and lower AND uppercasing the lower unit reproduces the
// original exactly. caseMask returns null when that is impossible — the
// lowering changed the length (`İ`) or a unit's uppercase expands (`ẞ`→`SS`) —
// and the caller keeps the original string instead. `lower` is
// original.toLowerCase(), which the caller already holds.

export function caseMask(original, lower) {
  const orig = String(original)
  const low = String(lower)
  if (low.length !== orig.length) return null
  const mask = new Uint8Array(Math.ceil(orig.length / 8))
  for (let i = 0; i < orig.length; i++) {
    if (orig[i] === low[i]) continue
    if (low[i].toUpperCase() !== orig[i]) return null
    mask[i >> 3] |= 1 << (i & 7)
  }
  return mask
}

export function applyCaseMask(lower, mask) {
  const low = String(lower)
  if (!mask) return low
  let out = ""
  for (let i = 0; i < low.length; i++) {
    const ch = low[i]
    out += (mask[i >> 3] & (1 << (i & 7))) ? ch.toUpperCase() : ch
  }
  return out
}

// ---- docs ------------------------------------------------------------------

// A doc, the indexed form of an entry: lowercased text and context (for phrase
// checks and the substring fallback), the case mask (or the original text
// when unmaskable), and a copy of the entry's fields with `text` emptied, since
// `text` and `mask` hold it. URLs are never searched, so no lowercased source
// copy is kept. The caller's entry is left untouched.
function toDoc(e) {
  const original = String(e.text || "")
  const lower = original.toLowerCase()
  const mask = caseMask(original, lower)
  const context = e.context
    ? [e.context.text, e.context.author, e.context.handle].join(" ").toLowerCase()
    : ""
  const entry = toEntry(e)
  entry.text = null
  return { text: lower, context: context, mask: mask, originalText: mask ? null : original, entry: entry }
}

// A doc's entry in the ENTRY_FIELDS shape, original case intact.
function docEntry(doc) {
  const entry = Object.assign({}, doc.entry)
  entry.text = doc.mask ? applyCaseMask(doc.text, doc.mask) : doc.originalText
  return entry
}

// The lowercased body a doc is searched by: the text minus its reply mentions.
function docBody(doc) {
  return withoutReplyMentions(doc.entry, doc.text)
}

// ---- index -----------------------------------------------------------------

// Build the index over `entries`:
//   docs            one doc per entry, in dataset order (date-ascending)
//   postings        the ranked-search postings and the trending counts
//                   (buildPostings)
//   priors          per-doc recency, quality and curated flags (buildPriors)
//   entryLookup     docs by id, source and text, for refreshEntries
//   scratch         per-doc accumulators reused by every search
export function buildIndex(entries) {
  const docs = entries.map(function(e) { return toDoc(e) })
  return { docs: docs, postings: buildPostings(docs), priors: buildPriors(docs),
           entryLookup: buildEntryLookup(docs), scratch: newScratch(docs.length) }
}

// Postings for ranked search: per term, the docs holding it with their term
// frequency packed 4 bits per field (FIELD_*), in one Int32Array of
// [doc, packedTf] pairs. Terms are numbered in first-seen order: `termId`
// maps a term to its id, `termById` back, and term id k owns
// pairs[offsets[k] .. offsets[k + 1]). `terms` is the sorted term list, for
// prefix ranges; the body and context lengths feed BM25. No text is copied.
// `trendCounts[id]` counts the term's body occurrences when it can trend
// (suggestable and not a stopword), else 0: trending terms come from the
// indexed bodies, so every trending term is searchable, and URL fragments
// ("https") never trend.
function buildPostings(docs) {
  const n = docs.length
  // A plain prototype-less object, not a Map: Qt's V4 Map lookups are
  // linear, which made this build quadratic (seconds) in the shell. Every
  // other per-term table is an array indexed by id, so this is the only
  // string-keyed lookup per token.
  const termId = Object.create(null)
  const termById = []
  const lists = []
  const lastSeen = []      // the last doc added to each term's list
  const trendable = []     // 1 when the term can trend
  const trendCounts = []
  const bodyLen = new Uint16Array(n)
  const contextLen = new Uint16Array(n)
  let totalBody = 0, totalContext = 0, contextCount = 0
  for (let i = 0; i < n; i++) {
    const doc = docs[i]
    const e = doc.entry
    const fields = [docBody(doc).replace(URL_RE, " "), "", "", ""]
    if (e.context) {
      fields[FIELD_CONTEXT] = String(e.context.text || "").toLowerCase().replace(URL_RE, " ")
      fields[FIELD_AUTHOR] = (String(e.context.author || "") + " " + String(e.context.handle || "")).toLowerCase()
    }
    if (e.title) fields[FIELD_TITLE] = String(e.title).toLowerCase()
    for (let f = 0; f < FIELD_COUNT; f++) {
      if (!fields[f]) continue
      const tokens = tokenize(fields[f])
      if (f === FIELD_BODY) { bodyLen[i] = Math.min(65535, tokens.length); totalBody += tokens.length }
      else if (f === FIELD_CONTEXT) { contextLen[i] = Math.min(65535, tokens.length); totalContext += tokens.length; contextCount++ }
      const shift = f * 4
      for (let k = 0; k < tokens.length; k++) {
        const t = tokens[k]
        let id = termId[t]
        if (id === undefined) {
          id = termById.length
          termId[t] = id
          termById.push(t)
          lists.push([])
          lastSeen.push(-1)
          trendable.push(isSuggestable(t) && !isStopword(t) ? 1 : 0)
          trendCounts.push(0)
        }
        if (f === FIELD_BODY) trendCounts[id] += trendable[id]
        const list = lists[id]
        if (lastSeen[id] !== i) { lastSeen[id] = i; list.push(i, 0) }
        const last = list.length - 1
        if (((list[last] >> shift) & 15) < 15) list[last] += 1 << shift
      }
    }
  }
  const offsets = new Int32Array(lists.length + 1)
  let total = 0
  for (let id = 0; id < lists.length; id++) { offsets[id] = total; total += lists[id].length }
  offsets[lists.length] = total
  const pairs = new Int32Array(total)
  for (let id = 0; id < lists.length; id++) pairs.set(lists[id], offsets[id])
  return { terms: termById.slice().sort(), termId: termId, termById: termById, offsets: offsets, pairs: pairs,
           bodyLen: bodyLen, contextLen: contextLen,
           avgBody: n && totalBody ? totalBody / n : 1, avgContext: contextCount && totalContext ? totalContext / contextCount : 1,
           trendCounts: Int32Array.from(trendCounts) }
}

// Per-doc multipliers: recency (1 for the newest post, halving every
// RECENCY_HALF_LIFE_YEARS; 0 when undated), quality (low-information replies
// and reposts of others' words rank a bit lower) and curated (the essay/book
// quotes).
function buildPriors(docs) {
  const n = docs.length
  const recency = new Float32Array(n)
  const quality = new Float32Array(n)
  const curated = new Uint8Array(n)
  const times = new Float64Array(n)
  let newest = 0
  for (let i = 0; i < n; i++) {
    const e = docs[i].entry
    const time = e.date ? Date.parse(e.date) : NaN
    times[i] = isNaN(time) ? -1 : time
    if (time > newest) newest = time
    let q = 1
    if (e.kind === "reply") {
      const bodyLength = docBody(docs[i]).length
      q = bodyLength < REPLY_SHORT_LENGTH ? SHORT_REPLY_QUALITY : bodyLength < REPLY_MEDIUM_LENGTH ? MEDIUM_REPLY_QUALITY : 1
    }
    else if (isRepost(e)) q = REPOST_QUALITY
    quality[i] = q
    curated[i] = e.type === "quote" && !e.kind ? 1 : 0
  }
  const yearMs = 365.25 * 864e5
  for (let i = 0; i < n; i++) {
    recency[i] = times[i] < 0 ? 0 : Math.pow(0.5, (newest - times[i]) / yearMs / RECENCY_HALF_LIFE_YEARS)
  }
  return { recency: recency, quality: quality, curated: curated }
}

// Docs by id, source, and lowercased text, for refreshEntries.
function buildEntryLookup(docs) {
  const byId = Object.create(null)
  const bySource = Object.create(null)
  const byText = Object.create(null)
  for (let i = 0; i < docs.length; i++) {
    const doc = docs[i]
    if (doc.entry.id) byId[doc.entry.id] = doc
    if (doc.entry.source) bySource[doc.entry.source] = doc
    byText[doc.text] = doc
  }
  return { byId: byId, bySource: bySource, byText: byText }
}

// Per-doc accumulators reused by every search: `matchedFilters[i]` holds one
// bit per filter doc i matches, and `stamp[i] === gen` marks the docs the
// current search has touched, so nothing is cleared per search.
function newScratch(n) {
  return { score: new Float64Array(n), best: new Float64Array(n), matchedFilters: new Uint32Array(n),
           stamp: new Uint32Array(n), gen: 0 }
}

// ---- ranked search ---------------------------------------------------------
//
// Whole words, never substrings: "on" does not match "Constraints" and "hey"
// does not match "they". URLs are never searched (a source of
// rubyonrails.org/doctrine is not a post about Rails). Matches are ranked:
//   - BM25F per query word over four fields, combined before saturation:
//     the body (reply @mentions and URLs removed) at weight 1, the
//     quoted/replied-to text (FIELD_WEIGHT_CONTEXT), its author and handle
//     (FIELD_WEIGHT_AUTHOR) and a link's title (FIELD_WEIGHT_TITLE).
//   - The last word matches as a prefix while it is still being typed (the
//     raw query does not end in a space or punctuation), weighted by
//     COMPLETION_WEIGHT_*; singular/plural variants match at PLURAL_WEIGHT
//     and -ing/-ed forms at INFLECTED_WEIGHT ("hotwire" finds "hotwiring").
//     None can outscore the word as typed.
//   - A word nothing matches at all is replaced by the most frequent term
//     one edit away ("omarcy" -> "omarchy"); the response's `correctedQuery`
//     is the query as searched, for the status line and the highlighter.
//   - Every non-stopword word must match (AND); stopwords only count toward
//     the phrase bonus. Two adjacent words written together also match
//     ("jason fried" finds @jasonfried).
//   - Multipliers: PHRASE_BONUS_BODY for the whole query in order in the
//     body (PHRASE_BONUS_CONTEXT in the quoted text), LEAD_BONUS when the
//     body opens with a query word, CURATED_PRIOR for the curated essay/book
//     quotes, up to RECENCY_BOOST for recency (halving every
//     RECENCY_HALF_LIFE_YEARS), and the quality of short replies and reposts
//     (buildPriors).
//   - Nothing matching every word: posts missing at most one word, scored
//     lower (CLOSE_MATCH_FACTOR). A stopword-only query ("the") lists posts
//     that open with it first, then the rest newest first. A query with no
//     word characters (CJK, emoji) falls back to a substring scan, newest
//     first.
// The tokenizer, the stopwords, the stems and the query parsing live in
// js/words.mjs, which js/highlight.mjs shares, so the highlighter bolds what
// these rules match.

// The most frequent indexed term one edit away from `word` (a deletion,
// transposition, substitution or insertion of a letter) that keeps its first
// letter, or null: typos rarely hit the first letter, and "async" must not
// become "sync". A word one edit from a stopword is left alone: typed
// directly the stopword would not filter, so "thier" must become neither a
// required "their" nor "tier". The neighbours are generated and looked up,
// ~54 x length lookups, rather than scanning the term list.
function correctTypo(postings, word, open) {
  if (word.length < (open ? TYPO_MIN_LENGTH_OPEN : TYPO_MIN_LENGTH)) return null
  let best = null
  let bestDf = 0
  let nearStopword = false
  function consider(t) {
    if (t === word || t[0] !== word[0]) return
    if (isStopword(t)) { nearStopword = true; return }
    if (postings.termId[t] === undefined) return
    const df = documentFrequency(postings, t)
    if (df > bestDf) { bestDf = df; best = t }
  }
  const n = word.length
  for (let i = 0; i < n; i++) {
    consider(word.slice(0, i) + word.slice(i + 1))
    if (i + 1 < n) consider(word.slice(0, i) + word[i + 1] + word[i] + word.slice(i + 2))
    for (let c = 0; c < ALPHABET.length; c++) {
      const ch = ALPHABET[c]
      if (ch !== word[i]) consider(word.slice(0, i) + ch + word.slice(i + 1))
      consider(word.slice(0, i) + ch + word.slice(i))
    }
  }
  for (let c = 0; c < ALPHABET.length; c++) consider(word + ALPHABET[c])
  return nearStopword ? null : best
}

// The terms one query word matches, with weights: [{ term, weight }]. The
// word itself, the `joined` terms spelling it together with a neighbour, then
// (unless `exactOnly`) the singular/plural forms of its `stem`, its -ing/-ed
// `forms` (words.mjs wordVariants) and, when `prefix`, its completions.
function expandWord(postings, word, options) {
  const joined = options.joined || []
  const out = []
  const seen = Object.create(null)
  const exact = postings.termId[word] !== undefined
  if (exact) { out.push({ term: word, weight: 1.0 }); seen[word] = true }
  for (let i = 0; i < joined.length; i++) {
    if (seen[joined[i]]) continue
    out.push({ term: joined[i], weight: 1.0 }); seen[joined[i]] = true
  }
  if (options.exactOnly) return out
  const stem = options.stem
  const plurals = [stem, stem + "s", stem + "es"]
  if (stem[stem.length - 1] === "y") plurals.push(stem.slice(0, -1) + "ies")
  for (let i = 0; i < plurals.length; i++) {
    const f = plurals[i]
    if (seen[f] || postings.termId[f] === undefined || pluralStem(f) !== stem) continue
    out.push({ term: f, weight: PLURAL_WEIGHT }); seen[f] = true
  }
  const forms = options.forms
  for (let i = 0; i < forms.length; i++) {
    const f = forms[i]
    if (seen[f] || postings.termId[f] === undefined) continue
    out.push({ term: f, weight: INFLECTED_WEIGHT }); seen[f] = true
  }
  if (options.prefix && word.length >= 2) {
    const terms = postings.terms
    for (let i = lowerBound(terms, word); i < terms.length && terms[i].startsWith(word); i++) {
      const t = terms[i]
      if (seen[t]) continue
      seen[t] = true
      const w = Math.min(COMPLETION_WEIGHT_MAX, COMPLETION_WEIGHT_BASE + COMPLETION_WEIGHT_BASE * word.length / t.length)
      out.push({ term: t, weight: exact ? w * COMPLETION_AFTER_EXACT : w })
    }
  }
  return out
}

// The index of the first term in the sorted `terms` that is not below
// `prefix`: where the terms starting with `prefix` begin, if any do.
function lowerBound(terms, prefix) {
  let lo = 0, hi = terms.length
  while (lo < hi) {
    const mid = (lo + hi) >> 1
    if (terms[mid] < prefix) lo = mid + 1
    else hi = mid
  }
  return lo
}

function documentFrequency(postings, t) {
  const k = postings.termId[t]
  return (postings.offsets[k + 1] - postings.offsets[k]) / 2
}

function inverseDocumentFrequency(n, df) {
  return Math.log(1 + (n - df + 0.5) / (df + 0.5))
}

// Strict "a ranks below b": lower score, or equal score and older position
// (the dataset is date-ascending, so a higher doc index is newer).
function ranksBelow(sa, ia, sb, ib) {
  return sa < sb || (sa === sb && ia < ib)
}

// The best `max` of a stream of (score, doc) pairs by ranksBelow: a size-max
// min-heap over typed arrays, so each offer costs O(log max) and the
// candidates are never sorted.
function TopK(max) {
  this.max = max
  this.scores = new Float64Array(max)
  this.docs = new Int32Array(max)
  this.size = 0
}

TopK.prototype.offer = function(score, doc) {
  const scores = this.scores, docs = this.docs, below = ranksBelow
  if (this.size < this.max) {
    let c = this.size++
    while (c > 0) {
      const parent = (c - 1) >> 1
      if (below(scores[parent], docs[parent], score, doc)) break
      scores[c] = scores[parent]; docs[c] = docs[parent]; c = parent
    }
    scores[c] = score; docs[c] = doc
  } else if (this.size > 0 && below(scores[0], docs[0], score, doc)) {
    const size = this.size
    let c = 0
    for (;;) {
      let l = 2 * c + 1
      if (l >= size) break
      if (l + 1 < size && below(scores[l + 1], docs[l + 1], scores[l], docs[l])) l++
      if (below(score, doc, scores[l], docs[l])) break
      scores[c] = scores[l]; docs[c] = docs[l]; c = l
    }
    scores[c] = score; docs[c] = doc
  }
}

// The kept docs, best first.
TopK.prototype.sorted = function() {
  const scores = this.scores, docs = this.docs, below = ranksBelow
  const order = []
  for (let k = 0; k < this.size; k++) order.push(k)
  order.sort(function(a, b) { return below(scores[a], docs[a], scores[b], docs[b]) ? 1 : -1 })
  return order.map(function(k) { return docs[k] })
}

// Rank the index for `query`, capped at `maxResults`. The response:
//   results         the best entries, best first, in the ENTRY_FIELDS shape
//   total           every match, exact
//   capped          total > maxResults
//   closeMatches    nothing matched every word; these are posts missing one
//   correctedQuery  the query as searched after typo correction, else ""
export function search(index, query, maxResults) {
  const raw = String(query || "").toLowerCase()
  const q = raw.trim()
  if (!q || !index) return searchResponse([], 0, maxResults, false, "")
  // The query parsed as js/highlight.mjs parses it (words.mjs parseQuery).
  // `parsed` is this search's own object: expandQuery records the typo
  // corrections on it.
  const parsed = parseQuery(raw)
  if (parsed.words.length === 0) return substringSearch(index, q, maxResults)
  const expansions = expandQuery(index.postings, parsed)
  const candidates = scoreCandidates(index, parsed, expansions)
  return rankCandidates(index, parsed, candidates, maxResults)
}

// The response search() documents.
function searchResponse(results, total, max, closeMatches, correctedQuery) {
  return { results: results, total: total, capped: total > max, closeMatches: closeMatches, correctedQuery: correctedQuery }
}

// Expand every filter into the terms it matches, correcting the words
// nothing matches, so the joined pairs can be rebuilt from the corrected
// words before any word is scored ("jasno fried" must still find
// @jasonfried). Returns one expansion list per filter. Records on `parsed`:
// `filters` capped at MAX_FILTERS, the corrections written into `words` and
// `rawWords`, `corrected` (some word was corrected) and `lastCorrected` (the
// open last word was).
function expandQuery(postings, parsed) {
  const words = parsed.words
  const rawWords = parsed.rawWords
  // A dangling one-letter word ("ruby on r") only steers the phrase bonus.
  const scoredCount = parsed.scoredCount
  if (parsed.filters.length > MAX_FILTERS) parsed.filters = parsed.filters.slice(0, MAX_FILTERS)
  const filters = parsed.filters
  // Joined pairs the index holds, attached to both of their words.
  const joinedFor = []
  for (let i = 0; i < scoredCount; i++) joinedFor.push([])
  for (let i = 0; i < parsed.joined.length; i++) {
    const j = parsed.joined[i]
    if (postings.termId[j] !== undefined) { joinedFor[i].push(j); joinedFor[i + 1].push(j) }
  }
  const expansions = []
  let corrected = false
  let lastCorrected = false
  for (let c = 0; c < filters.length; c++) {
    const filter = filters[c]
    const wi = filter.wordIndex
    const word = words[wi]
    let list = expandWord(postings, word, { prefix: filter.prefix, exactOnly: filter.exactOnly, joined: joinedFor[wi],
                                            stem: filter.stem, forms: filter.forms })
    if (list.length === 0 && !filter.exactOnly) {
      // Not exact-only, so `prefix` is exactly "the open last word".
      const fix = correctTypo(postings, word, filter.prefix)
      if (fix !== null) {
        words[wi] = fix
        rawWords[wi] = fix
        corrected = true
        if (filter.prefix) lastCorrected = true
        const variants = wordVariants(fix)
        list = expandWord(postings, fix, { prefix: false, exactOnly: false, joined: [],
                                           stem: variants.stem, forms: variants.forms })
      }
    }
    expansions.push(list)
  }
  if (corrected) {
    for (let i = 0; i + 1 < scoredCount; i++) {
      const j = words[i] + words[i + 1]
      if (postings.termId[j] === undefined) continue
      for (let c = 0; c < filters.length; c++) {
        const wi = filters[c].wordIndex
        if (wi !== i && wi !== i + 1) continue
        const list = expansions[c]
        let present = false
        for (let x = 0; x < list.length; x++) if (list[x].term === j) present = true
        if (!present) list.push({ term: j, weight: 1.0 })
      }
    }
  }
  parsed.corrected = corrected
  parsed.lastCorrected = lastCorrected
  return expansions
}

// Score every doc a filter reaches: per filter, the best BM25F score over
// its expansions, summed across filters (nothing for an all-stopword query,
// which ranks by position instead). Returns `docs`, the doc indices holding
// every filter, or, when none does and the query has more than one filter,
// every doc reached with `closeMatches` set.
function scoreCandidates(index, parsed, expansions) {
  const postings = index.postings
  const scratch = index.scratch
  const n = index.docs.length
  const words = parsed.words
  const filters = parsed.filters
  const allStopwords = parsed.allStopwords
  if (++scratch.gen >= 0xffffffff) { scratch.stamp.fill(0); scratch.gen = 1 }
  const gen = scratch.gen
  const score = scratch.score, best = scratch.best, matchedFilters = scratch.matchedFilters, stamp = scratch.stamp
  const bodyLen = postings.bodyLen, contextLen = postings.contextLen
  const avgBody = postings.avgBody, avgContext = postings.avgContext
  const pairs = postings.pairs, offsets = postings.offsets
  const k1 = BM25_K1, bBody = BM25_B_BODY, bContext = BM25_B_CONTEXT
  const wContext = FIELD_WEIGHT_CONTEXT, wAuthor = FIELD_WEIGHT_AUTHOR, wTitle = FIELD_WEIGHT_TITLE
  const touched = []
  for (let c = 0; c < filters.length; c++) {
    const word = words[filters[c].wordIndex]
    const list = expansions[c]
    const bit = 1 << c
    const wordTouched = []
    // Cap each expansion's idf at the word's own (the exact term's, or all
    // expansions' together) so a rare completion cannot outscore the word.
    let refDf = 0
    if (list.length && list[0].term === word) refDf = documentFrequency(postings, word)
    else for (let x = 0; x < list.length; x++) refDf += documentFrequency(postings, list[x].term)
    const refIdf = inverseDocumentFrequency(n, Math.min(n, refDf))
    for (let x = 0; x < list.length; x++) {
      const k = postings.termId[list[x].term]
      const from = offsets[k], to = offsets[k + 1]
      const idf = Math.min(refIdf, inverseDocumentFrequency(n, (to - from) / 2)) * list[x].weight
      for (let j = from; j < to; j += 2) {
        const i = pairs[j], packed = pairs[j + 1]
        let s = 0
        if (!allStopwords) {
          const tBody = (packed >> (FIELD_BODY * 4)) & 15
          const tContext = (packed >> (FIELD_CONTEXT * 4)) & 15
          const tAuthor = (packed >> (FIELD_AUTHOR * 4)) & 15
          const tTitle = (packed >> (FIELD_TITLE * 4)) & 15
          let tf = 0
          if (tBody) tf += tBody / (1 - bBody + bBody * bodyLen[i] / avgBody)
          if (tContext) tf += wContext * tContext / (1 - bContext + bContext * contextLen[i] / avgContext)
          if (tAuthor) tf += wAuthor * tAuthor
          if (tTitle) tf += wTitle * tTitle
          s = idf * tf * (k1 + 1) / (tf + k1)
        }
        if (stamp[i] !== gen) { stamp[i] = gen; score[i] = 0; matchedFilters[i] = 0; touched.push(i) }
        if (!(matchedFilters[i] & bit)) { matchedFilters[i] |= bit; best[i] = s; wordTouched.push(i) }
        else if (s > best[i]) best[i] = s
      }
    }
    for (let k = 0; k < wordTouched.length; k++) score[wordTouched[k]] += best[wordTouched[k]]
  }
  const need = filters.length === MAX_FILTERS ? 0x7fffffff : (1 << filters.length) - 1
  const docs = []
  for (let k = 0; k < touched.length; k++) if (matchedFilters[touched[k]] === need) docs.push(touched[k])
  if (docs.length === 0 && filters.length > 1 && !allStopwords) return { docs: touched, closeMatches: true }
  return { docs: docs, closeMatches: false }
}

// Apply the multipliers to each candidate's score and keep the best `max`:
// the phrase and lead bonuses, the curated, recency and quality priors and,
// for close matches, the share of words matched. An all-stopword query keeps
// only posts holding its phrase, those opening with it first.
function rankCandidates(index, parsed, candidates, max) {
  const docs = index.docs
  const score = index.scratch.score, matchedFilters = index.scratch.matchedFilters
  const recency = index.priors.recency, quality = index.priors.quality, curated = index.priors.curated
  const words = parsed.words
  const filters = parsed.filters
  const allStopwords = parsed.allStopwords
  const closeMatches = candidates.closeMatches
  const phraseOpen = parsed.lastWordOpen && !parsed.lastCorrected
  let phraseRe = null
  if (words.length > 1) phraseRe = phraseRegExp(parsed.rawWords, phraseOpen, false)
  // The body may open with reply mentions before the leading word.
  let leadRe
  if (allStopwords) {
    leadRe = new RegExp(LEADING_MENTIONS + phraseSource(words.map(escapeRegex)) + WORD_END)
  } else {
    const alts = []
    for (let c = 0; c < filters.length; c++) {
      const wi = filters[c].wordIndex
      const open = phraseOpen && wi === words.length - 1 && words[wi].length >= 2
      alts.push(escapeRegex(pluralStem(words[wi])) + (open ? "" : "(?:'s|s|es)?" + WORD_END))
    }
    // Any non-word characters but a mention's @ or a hashtag's # before it.
    leadRe = new RegExp(LEADING_MENTIONS + "[^" + WORD_CHARS + "@#]*(?:" + alts.join("|") + ")")
  }
  const top = new TopK(max)
  let total = 0
  for (let k = 0; k < candidates.docs.length; k++) {
    const i = candidates.docs[k]
    const doc = docs[i]
    let rel = score[i]
    if (allStopwords) {
      if (leadRe.test(doc.text)) rel = curated[i] ? 2 * CURATED_PRIOR : 2
      else rel = 1
    } else {
      if (curated[i]) rel *= CURATED_PRIOR
      if (!isRepost(doc.entry) && leadRe.test(doc.text)) rel *= LEAD_BONUS
    }
    if (closeMatches) {
      let h = matchedFilters[i], count = 0
      while (h) { count += h & 1; h >>>= 1 }
      if (count < Math.max(1, filters.length - 1)) continue
      rel *= (count / filters.length) * (count / filters.length) * CLOSE_MATCH_FACTOR
    }
    if (phraseRe) {
      if (phraseRe.test(doc.text)) rel *= PHRASE_BONUS_BODY
      else if (doc.entry.context && phraseRe.test(doc.context)) rel *= PHRASE_BONUS_CONTEXT
      else if (allStopwords) continue
    }
    total++
    top.offer(rel * (1 + RECENCY_BOOST * recency[i]) * quality[i], i)
  }
  const ranked = top.sorted()
  const results = []
  for (let k = 0; k < ranked.length; k++) results.push(docEntry(docs[ranked[k]]))
  // The corrected query ends in a space when its last word was corrected,
  // so the highlighter treats it as a complete word too. It is only reported
  // with results: a correction that still finds nothing is no result.
  const correctedQuery = parsed.corrected && total > 0 ? parsed.rawWords.join(" ") + (phraseOpen ? "" : " ") : ""
  return searchResponse(results, total, max, closeMatches && total > 0, correctedQuery)
}

// Queries with no letter or digit at all (CJK, emoji, "$"): the tokenizer
// cannot see them, so match as substrings of the text and context, newest
// first.
function substringSearch(index, q, max) {
  const docs = index.docs
  const results = []
  let total = 0
  for (let i = docs.length - 1; i >= 0; i--) {
    const doc = docs[i]
    if (!doc.text.includes(q) && !doc.context.includes(q)) continue
    total++
    if (results.length < max) results.push(docEntry(doc))
  }
  return searchResponse(results, total, max, false, "")
}

// ---- suggestions and trending ----------------------------------------------

// Up to `max` indexed terms starting with the trimmed lowercase query, in
// sorted order. Single letters and pure numbers are never suggested; every
// other term is one the search finds, so every suggestion has results. The
// term list is sorted, so the matches form one contiguous range:
// binary-search its start, then walk forward while the prefix holds.
export function suggestWords(index, query, max) {
  const prefix = String(query || "").trim().toLowerCase()
  if (!index || !prefix) return []
  const terms = index.postings.terms
  const out = []
  for (let i = lowerBound(terms, prefix); i < terms.length && out.length < max; i++) {
    const t = terms[i]
    if (!t.startsWith(prefix)) break
    if (isSuggestable(t)) out.push(t)
  }
  return out
}

// Reorder suggestions so trending terms lead (in trending order), followed by
// the rest in their original order.
export function prioritizeTrending(suggestions, trending) {
  const list = suggestions || []
  const lead = (trending || []).filter(function(t) { return list.includes(t) })
  if (lead.length === 0) return list
  return lead.concat(list.filter(function(w) { return !lead.includes(w) }))
}

// The `max` most frequent of `terms` by `counts` (counts[i] belongs to
// terms[i]; a zero count never ranks), ties in code-unit order. A partial
// top-k selection: O(n * max) instead of sorting all n terms.
export function topTerms(terms, counts, max) {
  // Whether term i ranks before term j.
  const before = (i, j) => counts[i] > counts[j] || (counts[i] === counts[j] && terms[i] < terms[j])
  const result = []
  const taken = new Uint8Array(terms.length)
  while (result.length < max) {
    let best = -1
    for (let i = 0; i < terms.length; i++) {
      if (taken[i] || counts[i] === 0) continue
      if (best < 0 || before(i, best)) best = i
    }
    if (best < 0) break
    result.push(terms[best])
    taken[best] = 1
  }
  return result
}

// ---- draws and history -----------------------------------------------------

// `count` random entries that avoid every excluded content key and do not
// repeat within the draw. Rejection sampling bounded at count * 8 picks, so a
// small dataset whose entries are mostly excluded cannot spin forever.
export function draw(index, count, excludedKeys) {
  if (!index || index.docs.length === 0) return []
  const docs = index.docs
  const excluded = Object.create(null)
  for (let i = 0; i < excludedKeys.length; i++) excluded[excludedKeys[i]] = true
  const entries = []
  const maxPicks = count * 8
  for (let picks = 0; picks < maxPicks && entries.length < count; picks++) {
    const entry = docEntry(docs[Math.floor(Math.random() * docs.length)])
    const key = contentKey(entry)
    if (excluded[key]) continue
    excluded[key] = true
    entries.push(entry)
  }
  return entries
}

// Replace each stored entry with its current dataset version, so a stored
// copy shows what the dataset holds now (a corrected source, a new verified
// badge, ...). Match priority id -> source -> text; an entry with no match,
// and every entry while there is no index yet, is kept as is.
export function refreshEntries(index, entries) {
  if (!index) return entries
  const lookup = index.entryLookup
  return entries.map(function(entry) {
    if (!entry || typeof entry !== "object") return entry
    const doc = (entry.id && lookup.byId[entry.id])
      || (entry.source && lookup.bySource[entry.source])
      || (entry.text && lookup.byText[String(entry.text).toLowerCase()])
    return doc ? docEntry(doc) : entry
  })
}
