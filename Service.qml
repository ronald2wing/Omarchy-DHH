import QtQuick
import Quickshell
import Quickshell.Io
import "search.js" as Search
import "format.js" as Fmt
import "state.js" as State

// Shared state for the DHH plugin. Carries the raw dataset text — loaded lazily
// on first panel open (ensureDatasetLoaded) rather than at bar startup, so the
// bar process holds no dataset until the panel is used.
Item {
  id: root

  property string datasetRaw: ""
  property var trendingTerms: []
  property bool datasetLoaded: false
  property var recentSearches: []
  property var history: []
  // Offline fallback subtitle; refreshed from the live profile count on first
  // open and left unchanged on any fetch error.
  property string postCount: "72.2K posts"
  property bool postCountRequested: false

  // Persisted history snapshots before dataset resolution. Set by loadHistory
  // and resolved into `history` by reconcileHistory once both the file and
  // datasetRaw are available; null means the file has not loaded yet.
  property var pendingHistory: null

  readonly property string datasetPath: Search.fileUrlToPath(Qt.resolvedUrl("data/quotes.jsonl"))
  readonly property string homeDir: Quickshell.env("HOME")
  readonly property string stateDir: homeDir + "/.local/state/dhh"
  readonly property string recentPath: stateDir + "/recent.json"
  readonly property string historyPath: stateDir + "/history.json"

  // Fetch DHH's live post count from a keyless profile endpoint.
  // Runs once (guarded by postCountRequested); on any failure — offline, non-200,
  // or a response shape without a numeric user.statuses — postCount keeps its
  // offline fallback default.
  function fetchPostCount() {
    if (root.postCountRequested) return
    root.postCountRequested = true
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
          root.postCount = Fmt.formatProfileCount(n) + " posts"
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

  // Load the dataset on first panel open instead of at bar mount, so the bar
  // process stays light until the panel is actually used. Idempotent:
  // datasetLoaded flips true in quotesFile.onLoaded (and onLoadFailed), so the
  // file is read at most once per process.
  function ensureDatasetLoaded() {
    if (root.datasetLoaded) return
    quotesFile.reload()
  }

  // Parse the persisted recent-query list; a missing file or bad JSON yields [].
  function loadRecentSearches(raw) {
    const parsed = State.parseJsonArray(raw)
    if (!parsed) { root.recentSearches = []; return }
    root.recentSearches = parsed
      .map(e => String(e || "").trim())
      .filter(s => s !== "")
  }

  // Record a query most-recent-first: skip empties, drop any existing
  // case-insensitive duplicate, unshift, cap at 6, persist.
  function rememberSearch(query) {
    const q = String(query || "").trim()
    if (q === "") return
    let list = State.recentSearchesExcluding(root.recentSearches, q)
    list.unshift(q)
    if (list.length > 6) list = list.slice(0, 6)
    const unchanged = list.length === root.recentSearches.length
      && list.every((e, i) => e === root.recentSearches[i])
    root.recentSearches = list
    if (unchanged) return
    recentStore.save()
  }

  // Remove a query from the recent list (trim + case-insensitive match) and
  // persist. No cap change — the list only shrinks here.
  function forgetSearch(query) {
    const q = String(query || "").trim()
    if (q === "") return
    root.recentSearches = State.recentSearchesExcluding(root.recentSearches, q)
    recentStore.save()
  }

  // Clear the entire recent-query list and persist an empty array so the
  // "Clear all" link in the search-history dropdown resets state on disk too.
  function clearRecentSearches() {
    root.recentSearches = []
    recentStore.save()
  }

  // Parse the persisted history array; a missing file or bad JSON yields [].
  // Only entries carrying a non-empty text string are kept. The raw snapshots
  // are staged in pendingHistory and resolved against the current dataset by
  // reconcileHistory (which runs once both the file and datasetRaw are
  // available), so the displayed history always reflects the live entry.
  function loadHistory(raw) {
    const parsed = State.parseJsonArray(raw)
    root.pendingHistory = parsed
      ? parsed.filter(e => e && typeof e === "object" && typeof e.text === "string" && String(e.text).trim() !== "")
      : []
    root.reconcileHistory()
  }

  // Map the pending history through resolveEntry, preserving order. Bail out
  // when there is nothing to reconcile, and defer dataset resolution until the
  // dataset has actually loaded, so the JSON Lines parse happens at most once
  // per startup (on the pass that has both inputs). The resolved history is
  // persisted only when it differs from the stored snapshots, so a pristine
  // file is not rewritten on every bar mount while a stale snapshot still
  // self-heals.
  function reconcileHistory() {
    const pending = root.pendingHistory
    if (pending === null || pending.length === 0) return
    const canResolve = root.datasetLoaded && root.datasetRaw !== ""
    const lookup = canResolve ? State.buildDatasetLookup(root.datasetRaw) : null
    const resolved = canResolve
      ? pending.map(e => State.resolveEntry(e, lookup))
      : pending.slice()
    root.history = resolved
    if (canResolve && JSON.stringify(resolved) !== JSON.stringify(pending)) {
      historyStore.save()
    }
  }

  // Record a history entry most-recent-first: drop any existing
  // case-insensitive duplicate by text, unshift, cap at 20, persist.
  function rememberEntry(entry) {
    const lower = String(entry.text || "").toLowerCase()
    let list = root.history.slice().filter(e => String(e.text || "").toLowerCase() !== lower)
    list.unshift(entry)
    if (list.length > 20) list = list.slice(0, 20)
    root.history = list
    historyStore.save()
  }

  FileView {
    id: quotesFile
    path: root.datasetPath
    printErrors: false
    onLoaded: {
      root.datasetRaw = text()
      root.datasetLoaded = true
      root.reconcileHistory()
    }
    onLoadFailed: {
      root.datasetRaw = ""
      root.trendingTerms = []
      root.datasetLoaded = true
    }
  }

  // Persisted state file: a FileView with atomic writes plus a one-shot retry
  // timer. The first write races the mkdir in Component.onCompleted, so on a
  // save failure it ensures the directory exists and retries once, serializing
  // the current `items` array. `applyLoaded` receives the raw file text on
  // load (or "" when the file is missing/unreadable).
  component PersistedFile: Item {
    id: store

    required property string path
    property var items: []
    property var applyLoaded: raw => {}

    function save() {
      fileView.setText(JSON.stringify(store.items) + "\n")
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
    items: root.recentSearches
    applyLoaded: raw => root.loadRecentSearches(raw)
  }

  PersistedFile {
    id: historyStore
    path: root.historyPath
    items: root.history
    applyLoaded: raw => root.loadHistory(raw)
  }

  Component.onCompleted: {
    root.ensureStateDir()
  }
}
