// WorkerScript entry of model/Dataset.qml: the message protocol over js/search.mjs.
import { parseJsonl } from "./entries.mjs"
import { buildIndex, search, suggestWords, prioritizeTrending, topTerms, draw, refreshEntries } from "./search.mjs"

const TRENDING_COUNT = 3
const MAX_SUGGESTIONS = 8
const MAX_DRAW = 50

// Module-scope state survives between messages.
let index = null
let trendingTerms = []
let pendingText = ""   // dataset text accumulated across chunked "index" messages

// Requests in, and the response each one gets:
//   { type: "index", text, done }           dataset text, possibly chunked
//       on `done`: { type: "indexed", trendingTerms }
//   { type: "search", query, maxResults }
//       { type: "searched", query, suggestions, results, total, capped,
//         closeMatches, correctedQuery }
//   { type: "draw", count, excludedKeys, tag }
//       { type: "drawn", tag, entries }     tag is echoed back
//   { type: "refresh", entries }            stored entries
//       { type: "refreshed", entries }      in the same order, each replaced
//                                           by its current dataset version
WorkerScript.onMessage = function(msg) {
  if (!msg || typeof msg.type !== "string") return

  switch (msg.type) {
  case "index":
    pendingText += typeof msg.text === "string" ? msg.text : ""
    if (msg.done !== true) return
    index = buildIndex(parseJsonl(pendingText))
    pendingText = ""
    trendingTerms = topTerms(index.postings.termById, index.postings.trendCounts, TRENDING_COUNT)
    WorkerScript.sendMessage({ type: "indexed", trendingTerms: trendingTerms })
    return

  case "search":
    WorkerScript.sendMessage(Object.assign({
      type: "searched",
      query: msg.query,
      suggestions: prioritizeTrending(suggestWords(index, msg.query, MAX_SUGGESTIONS), trendingTerms)
    }, search(index, msg.query, msg.maxResults)))
    return

  case "draw": {
    const count = Math.max(1, Math.min(msg.count || 1, MAX_DRAW))
    WorkerScript.sendMessage({ type: "drawn", tag: msg.tag, entries: draw(index, count, msg.excludedKeys || []) })
    return
  }

  case "refresh":
    WorkerScript.sendMessage({ type: "refreshed", entries: refreshEntries(index, msg.entries || []) })
    return
  }
}
