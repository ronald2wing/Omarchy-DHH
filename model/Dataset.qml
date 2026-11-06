pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import "../js/os.mjs" as Os

// The dataset, loaded on first open and held in a WorkerScript: search, random draws and refreshing stored entries.
Item {
  id: root

  // Bound to the panel's open state; the first true loads the dataset, so a
  // bar that never opens the panel holds no dataset. Once loaded, it stays.
  property bool active: false
  // True once the worker holds the index and can answer requests.
  readonly property bool ready: internal.ready
  // The dataset's most frequent searchable words, which lead the
  // suggestions; [] until ready.
  readonly property var trendingTerms: internal.trendingTerms

  // search()'s answer: { query, suggestions, results, total, capped,
  // closeMatches, correctedQuery }.
  signal searched(var response)
  // draw()'s answer. `tag` is whatever draw() passed, so a caller can tell
  // its own draws apart (the feed's, the no-results filler's, render
  // random's).
  signal drawn(var entries, string tag)
  // refresh()'s answer: the entries in the same order, each replaced by its
  // current dataset version when the dataset still has it.
  signal refreshed(var entries)

  onActiveChanged: { if (root.active) internal.loadRequested = true }
  Component.onCompleted: { if (root.active) internal.loadRequested = true }

  function search(query, maxResults) {
    worker.sendMessage({ type: "search", query: query, maxResults: maxResults })
  }

  // `count` random entries whose content keys are not in `excludedKeys`.
  function draw(count, excludedKeys, tag) {
    worker.sendMessage({ type: "draw", count: count, excludedKeys: excludedKeys, tag: String(tag || "") })
  }

  // Stored entries (matched by id, then source, then text).
  function refresh(entries) {
    worker.sendMessage({ type: "refresh", entries: entries })
  }

  QtObject {
    id: internal
    readonly property string datasetPath: Os.fileUrlToPath(Qt.resolvedUrl("../data/entries.jsonl"))
    property bool loadRequested: false
    property bool ready: false
    property var trendingTerms: []

    // Hand the dataset text to the worker. WorkerScript drops string payloads
    // above 16 MiB, and `length` counts UTF-16 units (up to 3 bytes each), so
    // chunks are capped at 4 Mi units and split only on line boundaries.
    function indexDataset(text) {
      const maxChunk = 4 * 1024 * 1024
      let start = 0
      do {
        let end = Math.min(start + maxChunk, text.length)
        if (end < text.length) {
          const newline = text.lastIndexOf("\n", end)
          if (newline > start) end = newline + 1
        }
        worker.sendMessage({ type: "index", text: text.slice(start, end), done: end >= text.length })
        start = end
      } while (start < text.length)
    }
  }

  FileView {
    // Empty until the first open, so the bar mount reads nothing from disk.
    // Binding the path (rather than calling reload() on a preload: false
    // view) is what makes the load happen: Quickshell 0.3's reload() on an
    // unloaded lazy view never emits loaded.
    path: internal.loadRequested ? internal.datasetPath : ""
    printErrors: false
    // The worker keeps the only long-lived copy of the text.
    onLoaded: internal.indexDataset(text())
    // An unreadable dataset still yields a working (empty) worker, so the
    // panel shows "No results for …" instead of loading forever.
    onLoadFailed: internal.indexDataset("")
  }

  WorkerScript {
    id: worker
    source: "../js/dataset-worker.mjs"
    onMessage: (msg) => {
      switch (msg.type) {
      case "indexed":
        internal.trendingTerms = msg.trendingTerms || []
        internal.ready = true
        break
      case "searched":
        root.searched(msg)
        break
      case "drawn":
        root.drawn(msg.entries || [], String(msg.tag || ""))
        break
      case "refreshed":
        root.refreshed(msg.entries || [])
        break
      }
    }
  }
}
