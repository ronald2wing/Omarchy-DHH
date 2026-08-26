import QtQuick
import Quickshell
import Quickshell.Io
import "search.js" as Search
import "format.js" as Fmt

// Shared state for the DHH plugin. Carries the parsed dataset (loaded eagerly
// at bar startup so the dataset is ready when the panel opens) and the render
// state the panel reads while a render is in flight.
Item {
  id: root

  property var entries: []
  property var trendingTerms: []
  property bool entriesLoaded: false
  property bool generating: false
  property bool renderPathDelivered: false
  property var recentQueries: []
  property var historyEntries: []
  // Offline fallback subtitle; refreshed from the live profile count on first
  // open and left unchanged on any fetch error.
  property string postCount: "72.2K posts"
  property bool postCountFetched: false

  readonly property string dataPath: Search.fileUrlToPath(Qt.resolvedUrl("data/quotes.jsonl"))
  readonly property string home: Quickshell.env("HOME")
  readonly property string stateDir: home + "/.local/state/dhh"
  readonly property string recentPath: stateDir + "/recent.json"
  readonly property string historyPath: stateDir + "/history.json"

  function onOpened() {
    root.refreshPostCount()
  }

  // Fetch DHH's live post count from the keyless fxtwitter profile endpoint.
  // Runs once (guarded by postCountFetched); on any failure — offline, non-200,
  // or a response shape without a numeric user.statuses — postCount keeps its
  // offline fallback default.
  function refreshPostCount() {
    if (root.postCountFetched) return
    root.postCountFetched = true
    const xhr = new XMLHttpRequest()
    xhr.open("GET", "https://api.fxtwitter.com/2/profile/dhh")
    xhr.timeout = 5000
    xhr.setRequestHeader("User-Agent", "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36")
    xhr.onreadystatechange = () => {
      if (xhr.readyState !== XMLHttpRequest.DONE) return
      if (xhr.status !== 200) return
      try {
        const data = JSON.parse(xhr.responseText)
        const n = data && data.user ? data.user.statuses : null
        if (typeof n === "number" && isFinite(n)) {
          root.postCount = Fmt.formatPosts(n) + " posts"
        }
      } catch (e) { /* leave postCount unchanged */ }
    }
    xhr.send()
  }

  // Ensure the on-disk state directory exists so the persisted stores can
  // write; the atomic FileView saves fail without it.
  function ensureStateDir() {
    Quickshell.execDetached(["mkdir", "-p", root.stateDir])
  }

  // Parse `raw` into an array; returns null on bad JSON or a non-array value.
  function parseArray(raw) {
    try {
      const parsed = JSON.parse(String(raw || ""))
      return Array.isArray(parsed) ? parsed : null
    } catch (e) { return null }
  }

  // Parse the persisted recent-query list; a missing file or bad JSON yields [].
  function applyRecent(raw) {
    const parsed = parseArray(raw)
    if (!parsed) { root.recentQueries = []; return }
    root.recentQueries = parsed
      .map(e => String(e || "").trim())
      .filter(s => s !== "")
  }

  // recentQueries minus any case-insensitive match for `query` (trimmed).
  function recentWithout(query) {
    const lower = String(query || "").trim().toLowerCase()
    return root.recentQueries.slice().filter(e => String(e).toLowerCase() !== lower)
  }

  // Record a query most-recent-first: skip empties, drop any existing
  // case-insensitive duplicate, unshift, cap at 6, persist.
  function recordRecentQuery(query) {
    const q = String(query || "").trim()
    if (q === "") return
    let list = recentWithout(q)
    list.unshift(q)
    if (list.length > 6) list = list.slice(0, 6)
    root.recentQueries = list
    recentStore.save()
  }

  // Remove a query from the recent list (trim + case-insensitive match) and
  // persist. No cap change — the list only shrinks here.
  function removeRecentQuery(query) {
    const q = String(query || "").trim()
    if (q === "") return
    root.recentQueries = recentWithout(q)
    recentStore.save()
  }

  // Clear the entire recent-query list and persist an empty array so the
  // "Clear all" link in the search-history dropdown resets state on disk too.
  function clearRecentQueries() {
    root.recentQueries = []
    recentStore.save()
  }

  // Parse the persisted history array; a missing file or bad JSON yields [].
  // Only entries carrying a non-empty text string are kept.
  function applyHistory(raw) {
    const parsed = parseArray(raw)
    if (!parsed) { root.historyEntries = []; return }
    root.historyEntries = parsed
      .filter(e => e && typeof e === "object" && typeof e.text === "string" && String(e.text).trim() !== "")
      .map(e => Search.pickEntry(e))
  }

  // Record a history entry most-recent-first: drop any existing
  // case-insensitive duplicate by text, unshift, cap at 20, persist.
  function recordHistoryEntry(entry) {
    const lower = String(entry.text || "").toLowerCase()
    let list = root.historyEntries.slice().filter(e => String(e.text || "").toLowerCase() !== lower)
    list.unshift(entry)
    if (list.length > 20) list = list.slice(0, 20)
    root.historyEntries = list
    historyStore.save()
  }

  FileView {
    id: quotesFile
    path: root.dataPath
    printErrors: false
    onLoaded: {
      const list = []
      text().split("\n").forEach(rawLine => {
        const line = rawLine.trim()
        if (line === "") return
        try { list.push(JSON.parse(line)) } catch (e) { /* skip malformed line */ }
      })
      root.entries = list
      root.entriesLoaded = true
    }
    onLoadFailed: {
      root.entries = []
      root.trendingTerms = []
      root.entriesLoaded = true
    }
  }

  // Persisted state file: a FileView with atomic writes plus a one-shot retry
  // timer. The first write races the mkdir in Component.onCompleted, so on a
  // save failure it ensures the directory exists and retries once, serializing
  // the current `state` array. `applyLoaded` receives the raw file text on
  // load (or "" when the file is missing/unreadable).
  component PersistedFile: Item {
    id: store

    required property string path
    property var state: []
    property var applyLoaded: raw => {}

    function save() {
      fileView.setText(JSON.stringify(store.state) + "\n")
    }

    FileView {
      id: fileView
      path: store.path
      atomicWrites: true
      printErrors: false
      onLoaded: store.applyLoaded(text())
      onLoadFailed: store.applyLoaded("")
      onSaveFailed: {
        root.ensureStateDir()
        retryTimer.restart()
      }
    }

    Timer {
      id: retryTimer
      interval: 500
      repeat: false
      onTriggered: store.save()
    }
  }

  PersistedFile {
    id: recentStore
    path: root.recentPath
    state: root.recentQueries
    applyLoaded: raw => root.applyRecent(raw)
  }

  PersistedFile {
    id: historyStore
    path: root.historyPath
    state: root.historyEntries
    applyLoaded: raw => root.applyHistory(raw)
  }

  Component.onCompleted: {
    root.ensureStateDir()
    quotesFile.reload()
  }
}
