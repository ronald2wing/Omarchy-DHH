// SearchWorker.js — runs DHH search off the UI thread. The entries array is
// cached in this worker's global scope after the one-time "init" message, so
// search messages only carry the query string.

// WorkerScripts run in a separate JS context and cannot use QML `import` or the
// `.import` directive. Qt.include() copies search.js's top-level functions here.
Qt.include("search.js")

var entries = null
var lowerEntries = null   // [{ t, s, c, entry }, ...]
var lowerVocab = null     // sorted array of unique lowercase words
var trendingTerms

WorkerScript.onMessage = function(msg) {
  // The worker may get internal QML messages without our expected keys;
  // drop anything that isn't an explicit init or search request.
  if (!msg || typeof msg.type !== "string") return

  if (msg.type === "init") {
    entries = msg.entries || []

    // Precompute lowercase fields once so search never re-lowercases per
    // keystroke. t/s/c are precomputed lowercase versions of the original
    // entry's text/source/context fields.
    lowerEntries = entries.map(function(e) {
      return {
        t: String(e.text || "").toLowerCase(),
        s: String(e.source || "").toLowerCase(),
        c: _contextText(e).toLowerCase(),
        entry: e
      }
    })

    // Precompute unique word vocabulary for prefix suggestions.
    var wordSet = Object.create(null)
    for (var i = 0; i < lowerEntries.length; i++) {
      var words = lowerEntries[i].t.split(/[^a-z']+/)
      for (var j = 0; j < words.length; j++) {
        if (words[j] && words[j].length >= 2) wordSet[words[j]] = true
      }
    }
    lowerVocab = Object.keys(wordSet).sort()

    // Reply immediately so workerReady=true and search can start; the
    // trending-term count (potentially slow at scale) runs after.
    WorkerScript.sendMessage({ type: "init", ok: true })

    // Compute trendingTerms in background after replying.
    trendingTerms = frequentTerms(entries, 3)
    WorkerScript.sendMessage({ type: "trending", trendingTerms: trendingTerms })
    return
  }
  if (msg.type !== "search") return
  if (!entries) {
    WorkerScript.sendMessage({ results: [], suggestions: [], query: msg.query, total: 0 })
    return
  }
  var found = searchEntriesFast(lowerEntries, msg.query, msg.maxResults)
  var suggestions = suggestWordsFast(lowerVocab, msg.query)
  WorkerScript.sendMessage({
    results: found.results,
    suggestions: suggestions,
    query: msg.query,
    total: found.total
  })
}
