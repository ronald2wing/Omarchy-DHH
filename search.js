// Shared DHH search and slug helpers. Locale- and Qt-free so they load via
// `import "search.js" as Search` in QML, `Qt.include` in the search worker,
// and `vm` in node tests.

// Decode a "file://" URL to a path. Returns the input unchanged when the scheme
// is absent; null only on a malformed %-escape.
function fileUrlToPath(url) {
  let s = String(url || "")
  if (s.indexOf("file://") === 0) {
    s = s.substring(7)
    if (s.charAt(0) !== "/") s = "/" + s
    try {
      s = decodeURIComponent(s)
    } catch (e) {
      s = null
    }
  }
  return s
}

// Strip one-or-more leading "@<handle>" mentions (plus following whitespace)
// that X auto-prepends to reply text. X prepends the handle of everyone in the
// reply chain, so all leading mentions are redundant in the rendered body.
// `handle` presence just signals "this is a reply/repost entry".
function stripReplyMention(text, handle) {
  if (!text || !handle) return text
  return text.replace(/^(?:@[\w]+\s+)+/, "")
}

// Match a single word as a substring (case-insensitive); a phrase matches when
// it appears verbatim or every word appears as a substring.
function _textMatchesQuery(q, words, text) {
  if (words.length === 1) return text.indexOf(words[0]) !== -1
  if (text.indexOf(q) !== -1) return true
  return words.every((w) => text.indexOf(w) !== -1)
}

// Entries with a `context` (kind reply/repost) carry the referenced post under
// `context`; its text/author/handle are search targets alongside the entry's
// own text and source.
function _contextText(e) {
  if (!e || !e.context) return ""
  return [e.context.text, e.context.author, e.context.handle].join(" ")
}

// Shared scan loop behind searchEntries/searchEntriesFast: walks `items`,
// counting every matcher hit (so `total` stays accurate past maxResults) and
// collecting the first `max` matches as picked entries. `matcher` receives the
// item plus the trimmed lowercase query and its whitespace-split words, and
// `getEntry` resolves the original entry object from a (possibly precomputed)
// item — identity for plain entries, `.entry` for lowerEntries.
function _scan(items, query, maxResults, matcher, getEntry) {
  const q = String(query || "").toLowerCase().trim()
  const max = typeof maxResults === "number" && maxResults > 0 ? maxResults : 40
  if (!q || !items) return { results: [], total: 0 }
  const words = q.split(/\s+/)
  const results = []
  let total = 0
  for (let i = 0; i < items.length; i++) {
    if (matcher(items[i], q, words)) {
      total++
      if (results.length < max) results.push(pickEntry(getEntry(items[i]), i))
    }
  }
  return { results: results, total: total }
}

// Search the entry texts and source URLs, scanning the whole dataset so the
// reported total is accurate even past maxResults. Returns `{ results, total }`
// where `results` holds the first `max` matches (their original fields plus the
// dataset index as `id`) in dataset order and `total` is the full match count.
function searchEntries(entries, query, maxResults) {
  return _scan(entries, query, maxResults,
    function(e, q, words) {
      return _textMatchesQuery(q, words, String(e.text || "").toLowerCase()) ||
             _textMatchesQuery(q, words, String(e.source || "").toLowerCase()) ||
             _textMatchesQuery(q, words, _contextText(e).toLowerCase())
    },
    function(e) { return e }
  )
}

// Match a query (as the trimmed lowercase string plus its whitespace-split
// words) against a precomputed entry whose t/s/c are the lowercased
// text/source/context strings. Reuses _textMatchesQuery so phrase and
// substring semantics stay identical to searchEntries.
function _textMatchesQueryFast(q, words, lowerEntry) {
  return _textMatchesQuery(q, words, lowerEntry.t)
    || _textMatchesQuery(q, words, lowerEntry.s)
    || _textMatchesQuery(q, words, lowerEntry.c)
}

// Precomputed-field variant of searchEntries. `lowerEntries` is a flat array of
// `{ t, s, c, entry }` where t/s/c are the lowercased text/source/context
// strings and `entry` is the original object. Reads the cached lowercase fields
// instead of re-lowercasing every entry per keystroke.
function searchEntriesFast(lowerEntries, query, maxResults) {
  return _scan(lowerEntries, query, maxResults,
    function(le, q, words) { return _textMatchesQueryFast(q, words, le) },
    function(le) { return le.entry }
  )
}

// Distinct lowercased words from entry texts (min length 2) in first-appearance
// order that start with the given prefix, capped at maxResults.
function suggestWords(entries, prefix, maxResults) {
  const p = String(prefix || "").trim().toLowerCase()
  const max = typeof maxResults === "number" && maxResults > 0 ? maxResults : 8
  if (p === "" || !entries) return []
  const out = []
  const seen = Object.create(null)
  for (let i = 0; i < entries.length && out.length < max; i++) {
    const words = String(entries[i].text || "").toLowerCase().split(/[^a-z']+/)
    for (let w = 0; w < words.length && out.length < max; w++) {
      const word = words[w]
      if (word.length < 2 || seen[word]) continue
      seen[word] = true
      if (word.indexOf(p) === 0) out.push(word)
    }
  }
  out.sort()
  return out
}

// Precomputed-vocabulary variant of suggestWords. `lowerVocab` is a sorted array
// of unique lowercase words; the trimmed lowercase query is matched as a prefix
// against that vocab, avoiding per-keystroke split()/toLowerCase() across every
// entry. Returns at most maxResults words in sorted order.
function suggestWordsFast(lowerVocab, query, maxResults) {
  const max = typeof maxResults === "number" && maxResults > 0 ? maxResults : 8
  if (!lowerVocab) return []
  const prefix = String(query || "").trim().toLowerCase()
  if (!prefix) return []
  const out = []
  for (let i = 0; i < lowerVocab.length && out.length < max; i++) {
    if (lowerVocab[i].indexOf(prefix) === 0) out.push(lowerVocab[i])
  }
  return out
}

// Filesystem-safe slug: lowercase, non-alphanumeric runs become "-", trimmed.
function slugify(text) {
  return String(text || "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 60)
}

// Content-derived identity: normalize() collapses case and whitespace so a
// given text always yields the same id; entryId() returns the first 8 hex chars
// of its SHA-256. search.js stays Qt-free and has no Node crypto module, so the
// hasher is passed in: hashHex(text) must return the hex digest of its input.
function normalize(text) {
  return String(text).trim().toLowerCase().replace(/\s+/g, " ")
}

function entryId(text, hashHex) {
  return hashHex(normalize(text)).slice(0, 8)
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
const _STOPWORDS = [
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

// Most-frequent terms across entry texts, excluding stopwords and tokens
// shorter than 2 chars. Returns up to `limit` terms sorted by frequency
// descending; ties break alphabetically. Tokenization matches suggestWords.
function frequentTerms(entries, limit) {
  const max = typeof limit === "number" && limit > 0 ? limit : 3
  if (!entries) return []
  const stop = Object.create(null)
  for (let s = 0; s < _STOPWORDS.length; s++) stop[_STOPWORDS[s]] = true
  const counts = Object.create(null)
  for (let i = 0; i < entries.length; i++) {
    const words = String(entries[i].text || "").toLowerCase().split(/[^a-z']+/)
    for (let w = 0; w < words.length; w++) {
      const word = words[w]
      if (word.length < 2 || stop[word]) continue
      counts[word] = (counts[word] || 0) + 1
    }
  }
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
