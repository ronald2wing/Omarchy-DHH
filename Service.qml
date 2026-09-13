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

  // Avatar cache: data URIs keyed by bare handle, populated by the bounded
  // fetch below (bin/omarchy-fetch-avatar). Reassigned, never mutated in place,
  // so QML bindings re-evaluate when the cache changes.
  property var avatarCache: ({})
  property var avatarPending: []
  property var avatarInFlight: []

  readonly property string datasetPath: Search.fileUrlToPath(Qt.resolvedUrl("data/quotes.jsonl"))
  readonly property string homeDir: Quickshell.env("HOME")
  readonly property string stateDir: homeDir + "/.local/state/dhh"
  readonly property string recentPath: stateDir + "/recent.json"
  readonly property string historyPath: stateDir + "/history.json"
  readonly property string profileCountScriptPath: Search.fileUrlToPath(Qt.resolvedUrl("bin/omarchy-fetch-profile-count"))
  readonly property int profileCountJsonMax: 64 * 1024
  readonly property string avatarScriptPath: Search.fileUrlToPath(Qt.resolvedUrl("bin/omarchy-fetch-avatar"))
  readonly property int avatarJsonMax: 4 * 1024 * 1024
  readonly property int avatarCacheMax: 256

  // Fetch DHH's live post count from a keyless profile endpoint.
  // Runs once (guarded by postCountRequested) via the bounded Ruby helper
  // bin/omarchy-fetch-profile-count, which prints the raw JSON body to stdout
  // (exit 0) or a one-line error to stderr (exit 1). The helper enforces its
  // own byte cap and deadline; the watchdogs below are a QML-side backstop. On
  // any failure the offline fallback default is left unchanged.
  function fetchPostCount() {
    if (root.postCountRequested) return
    root.postCountRequested = true
    profileCountProcess.exec([root.profileCountScriptPath])
    profileCountWatchdog.restart()
  }

  // Cancel an in-flight profile-count fetch: stop the watchdogs and hard-kill
  // the helper. Called when the panel closes and on Service destruction.
  function cancelPostCountFetch() {
    profileCountWatchdog.stop()
    profileCountKillWatchdog.stop()
    if (profileCountProcess.running) profileCountProcess.signal(9)
  }

  // Return the cached avatar data URI for a handle, or "" when uncached. Reads
  // root.avatarCache (not a local copy) so bindings re-evaluate when the cache
  // is reassigned.
  function avatarFor(handle) {
    const h = String(handle || "").replace(/^@/, "")
    return String(root.avatarCache[h] || "")
  }

  // Queue a set of handles for avatar fetching: coerce to strings, strip one
  // leading @, keep only handles matching the helper's pattern, dedupe, then
  // start the fetch. Handles already cached or in flight are skipped by
  // _startAvatarFetch.
  function fetchAvatars(handles) {
    root.avatarPending = (Array.isArray(handles) ? handles : [])
      .map(h => String(h || "").replace(/^@/, ""))
      .filter(h => /^[A-Za-z0-9_]{1,15}$/.test(h))
      .filter((h, i, a) => a.indexOf(h) === i)
    root._startAvatarFetch()
  }

  // Run one bounded batch of avatar fetches. Idempotent: returns while a batch
  // is running, and always terminates: each round caches every in-flight handle
  // (a data URI or ""), so `wanted` strictly shrinks.
  function _startAvatarFetch() {
    if (avatarProcess.running) return
    const wanted = root.avatarPending.filter(h => !(h in root.avatarCache) && root.avatarInFlight.indexOf(h) === -1)
    if (wanted.length === 0) return
    root.avatarInFlight = wanted
    avatarProcess.exec([root.avatarScriptPath].concat(wanted))
    avatarWatchdog.restart()
  }

  // Cancel all avatar fetching: stop the watchdogs, hard-kill the helper, and
  // clear the queues. Called when the panel closes and on Service destruction.
  function cancelAvatarFetch() {
    avatarWatchdog.stop()
    avatarKillWatchdog.stop()
    if (avatarProcess.running) avatarProcess.signal(9)
    root.avatarPending = []
    root.avatarInFlight = []
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

  // Bounded profile-count fetch: the Ruby helper caps the response size and
  // enforces its own deadline, but these timers are the QML-side backstop that
  // escalate SIGTERM -> SIGKILL if the helper hangs (the Quickshell Process
  // type exposes only signal(int), no group kill).
  Timer {
    id: profileCountWatchdog
    interval: 12000
    repeat: false
    onTriggered: {
      if (profileCountProcess.running) profileCountProcess.signal(15)
      profileCountKillWatchdog.restart()
    }
  }

  Timer {
    id: profileCountKillWatchdog
    interval: 3000
    repeat: false
    onTriggered: { if (profileCountProcess.running) profileCountProcess.signal(9) }
  }

  Process {
    id: profileCountProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        // Defense in depth on top of the helper's own cap: bound the parse cost
        // even if a misbehaving helper writes more than expected.
        if (!Fmt.withinByteLimit(text, root.profileCountJsonMax)) return
        try {
          const data = JSON.parse(text)
          const n = data && data.user ? data.user.statuses : null
          if (typeof n === "number" && isFinite(n)) {
            root.postCount = Fmt.formatProfileCount(n) + " posts"
          }
        } catch (e) { /* leave postCount unchanged */ }
      }
    }
    onExited: (exitCode) => {
      profileCountWatchdog.stop()
      profileCountKillWatchdog.stop()
    }
  }

  // Bounded avatar fetch: same QML-side backstop as the profile-count fetch —
  // SIGTERM on the watchdog, then SIGKILL on the kill watchdog if the helper
  // hangs. The helper itself caps the byte size and enforces its own deadline.
  Timer {
    id: avatarWatchdog
    interval: 12000
    repeat: false
    onTriggered: {
      if (avatarProcess.running) avatarProcess.signal(15)
      avatarKillWatchdog.restart()
    }
  }

  Timer {
    id: avatarKillWatchdog
    interval: 3000
    repeat: false
    onTriggered: { if (avatarProcess.running) avatarProcess.signal(9) }
  }

  Process {
    id: avatarProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        // Parse the helper's handle -> data-URI JSON object. On any parse
        // failure or an oversized response, every in-flight handle still lands
        // in the cache as "", so the batch always terminates.
        let parsed = null
        if (Fmt.withinByteLimit(text, root.avatarJsonMax)) {
          try { parsed = JSON.parse(text) } catch (e) { parsed = null }
        }
        const merged = {}
        root.avatarInFlight.forEach(h => {
          merged[h] = (parsed && typeof parsed[h] === "string" && parsed[h]) ? parsed[h] : ""
        })
        // A property var does not emit change on in-place mutation, so reassign
        // a fresh object. Bound the cache by resetting to just this round's
        // entries once it exceeds the cap.
        root.avatarCache = Object.assign({}, root.avatarCache, merged)
        if (Object.keys(root.avatarCache).length > root.avatarCacheMax) {
          root.avatarCache = Object.assign({}, merged)
        }
        root.avatarInFlight = []
        root._startAvatarFetch()
      }
    }
    onExited: (exitCode) => {
      avatarWatchdog.stop()
      avatarKillWatchdog.stop()
      root._startAvatarFetch()
    }
  }

  Component.onCompleted: {
    root.ensureStateDir()
  }

  Component.onDestruction: {
    root.cancelPostCountFetch()
    root.cancelAvatarFetch()
  }
}
