// Search highlighting: bolds what search matches, and a suggestion's completion.

import { escapeHtml } from "./format.mjs"
import { WORD_RE, URL_RE, pluralStem, normalizeToken, escapeRegex, phraseRegExp, parseQuery, tableOf } from "./words.mjs"

// The prepared queries (prepareQuery), keyed by the raw query string. A module is one instance
// per QML engine, so both monitors' panels share this cache; it is cleared
// whole once it holds MAX_CACHED_QUERIES entries (they are cheap to rebuild).
const MAX_CACHED_QUERIES = 64
let queryCache = Object.create(null)
let queryCacheSize = 0

export function cachedQueryCount() {
  return queryCacheSize
}

// A query prepared for highlighting, cached: the filters with their forms as
// lookup tables, the joined pairs as one, the phrase RegExp, and for a
// `wordless` query (no word characters) the substring RegExp.
function prepareQuery(query) {
  const raw = String(query || "")
  let prepared = queryCache[raw]
  if (prepared !== undefined) return prepared
  if (queryCacheSize >= MAX_CACHED_QUERIES) { queryCache = Object.create(null); queryCacheSize = 0 }
  const parsed = parseQuery(raw)
  const filters = parsed.filters.map(function(filter) {
    return { word: filter.word, stem: filter.stem, forms: tableOf(filter.forms), prefix: filter.prefix }
  })
  const wordless = parsed.words.length === 0
  const substringRe = wordless
    ? new RegExp("(" + raw.trim().toLowerCase().split(/\s+/).map(escapeRegex).join("|") + ")", "gi")
    : null
  prepared = { filters: filters, joined: tableOf(parsed.joined), wordless: wordless, substringRe: substringRe,
               phrase: parsed.words.length > 1 ? phraseRegExp(parsed.rawWords, parsed.lastWordOpen, true) : null }
  queryCache[raw] = prepared
  queryCacheSize++
  return prepared
}

// The raw length covering `kept` normalized characters of a token: the
// apostrophes normalizeToken drops still sit inside the bolded span.
function rawPrefixLength(rawTok, kept) {
  let count = 0
  for (let i = 0; i < rawTok.length; i++) {
    const ch = rawTok[i]
    if (ch !== "'" && ch !== "’") count++
    if (count === kept) return i + 1
  }
  return rawTok.length
}

// The length of the bolded part of a raw token, or 0.
function boldedLength(rawTok, prepared) {
  const t = normalizeToken(rawTok)
  if (prepared.joined[t]) return rawTok.length
  const filters = prepared.filters
  const stem = pluralStem(t)
  let bestPrefix = 0
  for (let i = 0; i < filters.length; i++) {
    const filter = filters[i]
    if (t === filter.word) return rawTok.length
    if (filter.stem !== null && stem === filter.stem) return rawTok.length
    if (filter.forms[t] === true) return rawTok.length
    if (filter.prefix && t.startsWith(filter.word)) bestPrefix = Math.max(bestPrefix, rawPrefixLength(rawTok, filter.word.length))
  }
  return bestPrefix
}

// Wrap each match in <b>…</b> inside an HTML-escaped copy of `text`. Matching
// runs on the raw text and each segment is escaped separately, so "amp"/"lt"
// never match inside an escaped entity.
//
// The rule is search's, through parseQuery: whole tokens, never substrings. A
// token is bolded when it equals a query word, is its singular/plural variant
// or an -ing/-ed form, spells two adjacent query words joined ("jasonfried"),
// or, for the last word while it is still being typed, starts with it; then
// only the typed prefix is bolded ("<b>Ra</b>ils"). Stopwords in a mixed query
// are bolded only inside an in-order phrase match of the whole query
// ("<b>Ruby on Rails</b>"); in an all-stopword query they are bolded as whole
// words. URLs are never highlighted (search never matches them). A query with
// no word characters at all bolds each of its whitespace-separated parts
// wherever it occurs; search's substring fallback instead matches the whole
// query.
export function highlightHtml(text, query) {
  const t = String(text || "")
  if (String(query || "").trim() === "") return escapeHtml(t)
  const prepared = prepareQuery(query)
  if (prepared.wordless) return highlightSubstrings(t, prepared.substringRe)
  // URL spans are never highlighted.
  const urls = []
  let m
  URL_RE.lastIndex = 0
  while ((m = URL_RE.exec(t)) !== null) urls.push([m.index, m.index + m[0].length])
  const ranges = []   // [start, end), in order, non-overlapping
  // Phrase occurrences of the whole query, bolded as one span. Run on a
  // lowercased copy; skipped if lowercasing changed the length.
  const lower = t.toLowerCase().replace(/’/g, "'")
  const phrase = prepared.phrase
  if (phrase && lower.length === t.length) {
    phrase.lastIndex = 0
    while ((m = phrase.exec(lower)) !== null) {
      const s = m.index + m[1].length, e = s + m[2].length
      if (m[0].length === 0) phrase.lastIndex++
      // Never inside a URL.
      let inUrl = false
      for (let k = 0; k < urls.length && !inUrl; k++) inUrl = urls[k][0] < e && urls[k][1] > s
      if (!inUrl) ranges.push([s, e])
    }
  }
  WORD_RE.lastIndex = 0
  let r = 0, u = 0
  const tokRanges = []
  while ((m = WORD_RE.exec(t)) !== null) {
    const s = m.index, e = s + m[0].length
    while (u < urls.length && urls[u][1] <= s) u++
    if (u < urls.length && urls[u][0] <= s) continue
    while (r < ranges.length && ranges[r][1] <= s) r++
    if (r < ranges.length && ranges[r][0] <= s) continue   // inside a phrase span
    const len = boldedLength(m[0], prepared)
    if (len > 0) tokRanges.push([s, s + len])
  }
  const all = ranges.concat(tokRanges).sort(function(a, b) { return a[0] - b[0] })
  let out = ""
  let last = 0
  for (let i = 0; i < all.length; i++) {
    if (all[i][0] < last) continue
    out += escapeHtml(t.slice(last, all[i][0])) + "<b>" + escapeHtml(t.slice(all[i][0], all[i][1])) + "</b>"
    last = all[i][1]
  }
  return out + escapeHtml(t.slice(last))
}

// For queries with no word characters ("&", "<", "."): every
// case-insensitive occurrence of each query part.
function highlightSubstrings(t, re) {
  re.lastIndex = 0
  let out = ""
  let last = 0
  let m
  while ((m = re.exec(t)) !== null) {
    if (m[0].length === 0) { re.lastIndex++; continue }
    out += escapeHtml(t.slice(last, m.index)) + "<b>" + escapeHtml(m[0]) + "</b>"
    last = m.index + m[0].length
  }
  return out + escapeHtml(t.slice(last))
}

// A suggestion with its completion bolded: the part the user already typed
// (the trimmed query, when the suggestion starts with it) stays regular.
export function completionHtml(word, query) {
  const w = String(word || "")
  const q = String(query || "").trim()
  const matched = q.length > 0 && w.toLowerCase().startsWith(q.toLowerCase()) ? q.length : 0
  const head = escapeHtml(w.substring(0, matched))
  const tail = escapeHtml(w.substring(matched))
  return matched > 0 ? head + "<b>" + tail + "</b>" : head + tail
}
