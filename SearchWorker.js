// SearchWorker.js — runs DHH search off the UI thread. The lowered dataset is
// cached in this worker's global scope after the one-time "init" message, so
// search messages only carry the query string.

// WorkerScripts run in a separate JS context and cannot use QML `import` or the
// `.import` directive. Qt.include() copies search.js's top-level functions here.
Qt.include("search.js")

var lowerEntries = null   // [{ t, s, c, mask, origText?, entry }, ...]
var lowerVocab = null     // sorted array of unique lowercase words
var initBuffer = ""       // accumulates chunked init messages until the final chunk

function parseJsonl(raw) {
  const out = []
  const lines = String(raw || "").split("\n")
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim()
    if (line === "") continue
    try { out.push(JSON.parse(line)) } catch (e) { /* skip malformed line */ }
  }
  return out
}

// Reconstruct an item's original-case text: masked items rebuild from the
// lowered `t` plus their case mask; unmaskable items kept the original string
// in `origText`.
function originalItemText(item) {
  return item.mask ? restoreCase(item.t, item.mask) : item.origText
}

// Resolve the picked entry for an item, restoring its original-case text. `id`
// (the dataset index) is passed straight to pickEntry, exactly as the scan's
// getEntry contract expects.
function pickEntryForItem(item, id) {
  return pickEntry(Object.assign({}, item.entry, { text: originalItemText(item) }), id)
}

// Content identity of an entry: its source string, falling back to body text.
// Entry ids are unreliable (random draws have none; history ids may be numeric
// or a string hash), so the feed's no-repeat invariant keys on content only.
// Mirrors Panel.qml's feedContentKey; both sides must agree.
function contentKey(e) {
  return String((e && e.source) || (e && e.text) || "")
}

// Draw `count` random entries that avoid every excluded key and do not repeat
// within the batch. Bounded rejection sampling: at most count*8 draws, so a
// small dataset whose entries are mostly excluded cannot spin forever.
function drawRandomBatch(count, excludedKeys) {
  const excluded = Object.create(null)
  for (let i = 0; i < excludedKeys.length; i++) excluded[excludedKeys[i]] = true
  const batch = []
  const seen = Object.create(null)
  const maxDraws = count * 8
  for (let draws = 0; draws < maxDraws && batch.length < count; draws++) {
    const item = lowerEntries[Math.floor(Math.random() * lowerEntries.length)]
    const entry = pickEntryForItem(item)
    const key = contentKey(entry)
    if (excluded[key] || seen[key]) continue
    batch.push(entry)
    seen[key] = true
  }
  return batch
}

WorkerScript.onMessage = function(msg) {
  // The worker may get internal QML messages without our expected keys;
  // drop anything that isn't an explicit init or search request.
  if (!msg || typeof msg.type !== "string") return

  if (msg.type === "init") {
    initBuffer += (typeof msg.raw === "string" ? msg.raw : "")
    if (msg.done !== true) { return }          // wait for the final chunk
    const rawText = initBuffer
    initBuffer = ""
    const parsed = parseJsonl(rawText) || []

    // Precompute lowercase fields once so search never re-lowercases per
    // keystroke. t/s/c are precomputed lowercase versions of the original
    // entry's text/source/context fields. To avoid retaining two full copies of
    // every text (original + lowered), the original is reconstructed from `t`
    // plus a per-code-unit case mask; only entries the mask cannot reproduce
    // (length-changing lowercasing, e.g. `İ`) keep their original text in
    // `origText`. The parsed object's own `text` is deleted once masked so it
    // no longer holds the original string.
    lowerEntries = parsed.map(function(e) {
      const original = String(e.text || "")
      const t = original.toLowerCase()
      const mask = caseMaskFor(original, t)
      const item = {
        t: t,
        s: String(e.source || "").toLowerCase(),
        c: _contextText(e).toLowerCase(),
        mask: mask,
        entry: e
      }
      if (mask) {
        delete e.text
      } else {
        item.origText = original
      }
      return item
    })

    // Precompute the unique word vocabulary for prefix suggestions and the
    // trending-term counts in a single tokenization pass.
    const wordSet = Object.create(null)
    const termCounts = Object.create(null)
    const stop = _stopwordTable()
    for (let i = 0; i < lowerEntries.length; i++) {
      const words = _splitWords(lowerEntries[i].t)
      for (let j = 0; j < words.length; j++) {
        const word = words[j]
        if (word.length >= 2) {
          wordSet[word] = true
          if (!stop[word]) termCounts[word] = (termCounts[word] || 0) + 1
        }
      }
    }
    lowerVocab = Object.keys(wordSet).sort()

    // Reply immediately so workerReady=true and search can start; the
    // trending-term count (potentially slow at scale) runs after.
    WorkerScript.sendMessage({ type: "init", ok: true })

    // Compute trendingTerms in background after replying.
    const trendingTerms = topTerms(termCounts, 3)
    WorkerScript.sendMessage({ type: "trending", trendingTerms: trendingTerms })
    return
  }
  if (msg.type === "random") {
    const item = lowerEntries && lowerEntries.length
      ? lowerEntries[Math.floor(Math.random() * lowerEntries.length)]
      : null
    WorkerScript.sendMessage({
      type: "random",
      entry: item ? pickEntryForItem(item) : null
    })
    return
  }
  if (msg.type === "randomBatch") {
    const count = Math.max(1, Math.min(msg.count || 12, 50))
    const batch = lowerEntries && lowerEntries.length
      ? drawRandomBatch(count, msg.excludeKeys || [])
      : []
    WorkerScript.sendMessage({ type: "randomBatch", batch: batch })
    return
  }
  if (msg.type !== "search") return
  if (!lowerEntries) {
    WorkerScript.sendMessage({ results: [], suggestions: [], query: msg.query, total: 0 })
    return
  }
  const found = _scan(lowerEntries, msg.query, msg.maxResults,
    function(le, q, words) { return _textMatchesQueryFast(q, words, le) },
    pickEntryForItem
  )
  const suggestions = suggestWordsFast(lowerVocab, msg.query)
  WorkerScript.sendMessage({
    results: found.results,
    suggestions: suggestions,
    query: msg.query,
    total: found.total,
    capped: found.capped
  })
}
