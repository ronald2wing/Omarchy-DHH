// Shared DHH search helpers. Locale- and Qt-free so they load via
// `import "search.js" as Search` in QML, `Qt.include` in the search worker,
// and `vm` in node tests.
//
// The worker Qt.includes this file and uses its scan/match/suggest/word helpers plus the case-mask, context, and pickEntry reconstruction helpers; pickEntryForItem itself lives in SearchWorker.js.

// Decode a "file://" URL to a path. Returns the input unchanged when the scheme
// is absent; a malformed %-escape falls back to the undecoded path (the value is
// only used for local file access, so the raw path is the correct fallback).
function fileUrlToPath(url) {
  let s = String(url || "")
  if (s.startsWith("file://")) {
    s = s.substring(7)
    if (s.charAt(0) !== "/") s = "/" + s
    try {
      s = decodeURIComponent(s)
    } catch (e) {
      // Malformed %-escape: keep the undecoded path.
    }
  }
  return s
}

// Strip one-or-more leading "@<handle>" mentions (plus following whitespace)
// that X auto-prepends to reply text. X prepends the handle of everyone in the
// reply chain, so all leading mentions are redundant in the rendered body.
// `handle` presence just signals "this is a reply/repost entry".
function stripLeadingMentions(text, handle) {
  text = String(text || "")
  handle = String(handle || "")
  if (!text || !handle) return text
  return text.replace(/^(?:@[\w]+\s+)+/, "")
}

// Match a single word as a substring (case-insensitive); a phrase matches when
// it appears verbatim or every word appears as a substring.
function _textMatchesQuery(q, words, text) {
  if (words.length === 1) return text.includes(words[0])
  if (text.includes(q)) return true
  return words.every((w) => text.includes(w))
}

// Entries with a `context` (kind reply/repost) carry the referenced post under
// `context`; its text/author/handle are search targets alongside the entry's
// own text and source.
function _contextText(e) {
  if (!e || !e.context) return ""
  return [e.context.text, e.context.author, e.context.handle].join(" ")
}

// The quoted post's handle (reply/repost `context`), or "" when absent.
// Coerced to a string so a non-string handle in a hand-edited dataset line
// cannot throw in callers that string-concatenate or `.replace` it.
function contextHandleOf(e) {
  return e && e.context && e.context.handle ? String(e.context.handle || "") : ""
}

// Resolve a context author's avatar via unavatar.io (dynamic, fetched online at
// runtime). Strips the leading '@' — the resolver expects the bare handle.
// Returns "" for a missing handle (no avatar rendered).
function contextAvatarUrl(handle) {
  const h = String(handle || "")
  return h ? "https://unavatar.io/x/" + encodeURIComponent(h.replace(/^@/, "")) : ""
}

// Clamp a caller-supplied max/count to a positive number, falling back to
// `fallback` when the argument is not a positive number.
function _clampMax(n, fallback) {
  return typeof n === "number" && n > 0 ? n : fallback
}

// Shared scan loop used by the search worker: walks `items`, counting every
// matcher hit (so `total` stays accurate past maxResults) and collecting the
// first `max` matches. `matcher` receives the item plus the trimmed lowercase
// query and its whitespace-split words, and `getEntry(item, i)` resolves the
// final picked entry for a match — `pickEntry` of the raw entry, or a worker
// helper that first reconstructs the original-case text from a mask. The scan
// stops as soon as `total` reaches `max + 1` (enough to know the list is
// truncated), reports that count, and sets `capped: true`; if the dataset is
// exhausted first it sets `capped: false` with the exact `total`.
function _scan(items, query, maxResults, matcher, getEntry) {
  const q = String(query || "").toLowerCase().trim()
  const max = _clampMax(maxResults, 40)
  if (!q || !items) return { results: [], total: 0, capped: false }
  const words = q.split(/\s+/)
  const results = []
  let total = 0
  for (let i = 0; i < items.length; i++) {
    if (matcher(items[i], q, words)) {
      total++
      if (results.length < max) results.push(getEntry(items[i], i))
      if (total >= max + 1) return { results: results, total: total, capped: true }
    }
  }
  return { results: results, total: total, capped: false }
}

// Match a query (as the trimmed lowercase string plus its whitespace-split
// words) against a precomputed entry whose t/s/c are the lowercased
// text/source/context strings. Reuses _textMatchesQuery so phrase and
// substring semantics stay consistent across callers.
function _textMatchesQueryFast(q, words, lowerEntry) {
  return _textMatchesQuery(q, words, lowerEntry.t)
    || _textMatchesQuery(q, words, lowerEntry.s)
    || _textMatchesQuery(q, words, lowerEntry.c)
}

// Precomputed-vocabulary prefix lookup. `lowerVocab` is a sorted array
// of unique lowercase words; the trimmed lowercase query is matched as a prefix
// against that vocab, avoiding per-keystroke split()/toLowerCase() across every
// entry. Returns at most maxResults words in sorted order.
function suggestWordsFast(lowerVocab, query, maxResults) {
  const max = _clampMax(maxResults, 8)
  if (!lowerVocab) return []
  const prefix = String(query || "").trim().toLowerCase()
  if (!prefix) return []
  // lowerVocab is sorted, so prefix matches form a contiguous range. Binary
  // search the lower bound (first word >= prefix), then walk forward while the
  // prefix still matches.
  let lo = 0
  let hi = lowerVocab.length
  while (lo < hi) {
    const mid = (lo + hi) >> 1
    if (lowerVocab[mid] < prefix) lo = mid + 1
    else hi = mid
  }
  const out = []
  for (let i = lo; i < lowerVocab.length && out.length < max; i++) {
    if (!lowerVocab[i].startsWith(prefix)) break
    out.push(lowerVocab[i])
  }
  return out
}

// Build a per-code-unit uppercase mask for `original` so the original string
// can be reconstructed from `original.toLowerCase()` alone. `lower` defaults to
// that lowercased form and is accepted explicitly so the worker can reuse the
// `t` it already computed. Bit i (LSB-first per byte, `mask[i>>3] & (1<<(i&7))`)
// is set when code unit i differs between `original` and `lower` AND uppercasing
// that lower code unit reproduces the original exactly. Returns null when the
// original cannot be reconstructed this way — lowercasing changed the length
// (e.g. `İ` lowercases to `i` + a combining dot) or a differing unit's
// uppercase expands to a different string (e.g. `ẞ` uppercases to `SS`). The
// caller must then retain the original text instead of a mask.
function caseMaskFor(original, lower) {
  const orig = String(original)
  const low = lower === undefined ? orig.toLowerCase() : String(lower)
  if (low.length !== orig.length) return null
  const mask = new Uint8Array(Math.ceil(orig.length / 8))
  for (let i = 0; i < orig.length; i++) {
    if (orig[i] === low[i]) continue
    if (low[i].toUpperCase() !== orig[i]) return null
    mask[i >> 3] |= 1 << (i & 7)
  }
  return mask
}

// Reconstruct the original-case string from its lowercased copy plus a case
// mask (see caseMaskFor). For each code unit whose mask bit is set (LSB-first
// per byte), the unit is uppercased; every other unit passes through unchanged.
// Each masked unit was verified at mask-build time to uppercase back to the
// original, so the result is exact by construction. A null/absent mask returns
// `lower` unchanged.
function restoreCase(lower, mask) {
  const low = String(lower)
  if (!mask) return low
  let out = ""
  for (let i = 0; i < low.length; i++) {
    const ch = low[i]
    out += (mask[i >> 3] & (1 << (i & 7))) ? ch.toUpperCase() : ch
  }
  return out
}

// The canonical entry shape returned by search results and reused wherever a
// caller needs an entry's displayable fields: text/type/source/date/context/
// kind/title/domain. `id` is optional — search results pass the dataset index
// so callers can identify the row, while every other caller omits it, leaving
// the returned object with no `id` property.
function pickEntry(e, id) {
  const picked = { text: e.text, type: e.type, source: e.source, date: e.date,
                   context: e.context, kind: e.kind, title: e.title, domain: e.domain }
  if (id !== undefined) picked.id = id
  return picked
}

// Common English stopwords excluded from the trending-term count. Lowercased
// to match the tokenizer, which lowercases and splits on non a-z/apostrophe.
//
// WHY var, not const: this file is Qt.include'd into a WorkerScript, and
// top-level lexical bindings (const/let) are GC-collected from under the
// worker once the dataset is large enough (Qt 6.11.2 libQt6QmlWorkerScript),
// so any top-level state here must be a `var` (a global-object property).
var _STOPWORDS = [
  "a", "about", "above", "after", "again", "against", "all", "am", "an", "and",
  "any", "are", "aren't", "as", "at", "be", "because", "been", "before", "being",
  "below", "between", "both", "but", "by", "can", "can't", "cannot", "could",
  "couldn't", "did", "didn't", "do", "does", "doesn't", "doing", "don't", "down",
  "during", "each", "few", "for", "from", "further", "had", "hadn't", "has",
  "hasn't", "have", "haven't", "having", "he", "he'd", "he'll", "he's", "her",
  "here", "here's", "hers", "herself", "him", "himself", "his", "how", "how's",
  "i", "i'd", "i'll", "i'm", "i've", "if", "in", "into", "is", "isn't", "it",
  "it's", "its", "itself", "let's", "me", "more", "most", "mustn't", "my",
  "myself", "no", "nor", "not", "of", "off", "on", "once", "only", "or", "other",
  "ought", "our", "ours", "ourselves", "out", "over", "own", "same", "shan't",
  "she", "she'd", "she'll", "she's", "should", "shouldn't", "so", "some", "such",
  "than", "that", "that's", "the", "their", "theirs", "them", "themselves",
  "then", "there", "there's", "these", "they", "they'd", "they'll", "they're",
  "they've", "this", "those", "through", "to", "too", "under", "until", "up",
  "very", "was", "wasn't", "we", "we'd", "we'll", "we're", "we've", "were",
  "weren't", "what", "what's", "when", "when's", "where", "where's", "which",
  "while", "who", "who's", "whom", "why", "why's", "with", "won't", "would",
  "wouldn't", "you", "you'd", "you'll", "you're", "you've", "your", "yours",
  "yourself", "yourselves"
]

// Memoized stopword lookup table, built once from _STOPWORDS so every
// tokenization pass shares one object. `_stopTable` is a top-level `var` (see
// the _STOPWORDS note) so it survives the WorkerScript GC.
var _stopTable = null
function _stopwordTable() {
  if (_stopTable === null) {
    const stop = Object.create(null)
    for (let s = 0; s < _STOPWORDS.length; s++) stop[_STOPWORDS[s]] = true
    _stopTable = stop
  }
  return _stopTable
}

// Lowercase a text and split it on non a-z/apostrophe runs.
function _splitWords(text) {
  return String(text || "").toLowerCase().split(/[^a-z']+/)
}

// Select the top-`limit` terms from a word -> count map, sorted by frequency
// descending; ties break alphabetically.
function topTerms(counts, limit) {
  const max = _clampMax(limit, 3)
  const keys = Object.keys(counts)
  if (keys.length <= max) return keys.sort((a, b) => counts[b] - counts[a] || a.localeCompare(b))
  // Partial top-k: pick the highest-frequency terms one at a time. O(n * max)
  // instead of O(n log n). When max=3 and n=200k, this sorts 3 items instead
  // of 200k.
  const result = []
  const seen = Object.create(null)
  while (result.length < max) {
    let best = null
    for (let k = 0; k < keys.length; k++) {
      if (seen[keys[k]]) continue
      if (best === null || counts[keys[k]] > counts[best] || (counts[keys[k]] === counts[best] && keys[k] < best)) {
        best = keys[k]
      }
    }
    if (best === null) break
    result.push(best)
    seen[best] = true
  }
  return result
}
