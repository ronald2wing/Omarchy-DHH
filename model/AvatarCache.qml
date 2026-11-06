pragma ComponentBehavior: Bound
import QtQuick
import "../js/entries.mjs" as Entries

// Context-author avatars as data URIs by bare handle, fetched in batches by helpers/fetch-avatars.
Item {
  id: root

  // Bound to the panel's open state: opening requests the `requestOnOpen`
  // entries' avatars, closing cancels the batch in flight.
  property bool active: false
  // Entries whose avatars are requested on every open (BarWidget binds the
  // history, which heads the feed).
  property var requestOnOpen: []

  // Fetched handles settled (an avatar or ""): an awaited fetch may be done.
  signal settled()

  onActiveChanged: root.active ? root.request(root.requestOnOpen) : internal.cancel()
  Component.onCompleted: { if (root.active) root.request(root.requestOnOpen) }

  // The cached avatar data URI of the entry's context author, or "" while
  // unsettled or after a failed fetch.
  function contextAvatarFor(entry) {
    const handle = internal.bareContextHandle(entry)
    return internal.isSettled(handle) ? String(internal.cache[handle] || "") : ""
  }

  // Whether the entry's context author has an avatar still to fetch: the
  // cache is active, the handle is one the helper accepts, and it is not
  // settled.
  function awaitsFetch(entry) {
    const handle = internal.bareContextHandle(entry)
    return root.active && Entries.isValidHandle(handle) && !internal.isSettled(handle)
  }

  // Fetch the avatars of the context authors of `entries`: one leading @
  // stripped, only handles the helper accepts, each once. The newest
  // request replaces any queue not yet in flight: only the rows on screen
  // matter.
  function request(entries) {
    if (!root.active) return
    internal.queue = (entries || [])
      .map(e => internal.bareContextHandle(e))
      .filter(h => Entries.isValidHandle(h))
      .filter((h, i, all) => all.indexOf(h) === i)
    internal.fetchNextBatch()
  }

  QtObject {
    id: internal
    readonly property int maxAvatars: 256
    readonly property int maxBatch: 64 // helpers/fetch-avatars' MAX_HANDLES
    // Data URIs keyed by bare handle, "" for a fetch that failed: a handle in
    // it is settled. Replaced, never mutated in place, so bindings that call
    // contextAvatarFor() re-evaluate. No prototype, so a handle such as
    // "constructor" or "__proto__" (both valid on x.com) never resolves
    // through one.
    property var cache: Object.create(null)
    property var queue: []
    property var inFlight: []

    // The bare handle of the entry's context author ("" when it has none).
    function bareContextHandle(entry) {
      return Entries.bareHandle(Entries.contextHandle(entry))
    }

    // Whether the handle's fetch has finished, with or without an avatar.
    function isSettled(handle) {
      return Object.prototype.hasOwnProperty.call(internal.cache, handle)
    }

    function cancel() {
      process.cancel()
      internal.queue = []
      internal.inFlight = []
    }

    // Run one batch of unsettled handles. Each round settles every handle it
    // fetched (a data URI or ""), so the next round's filter excludes them
    // and the queue always drains.
    function fetchNextBatch() {
      if (process.running) return
      const wanted = internal.queue.filter(h => !internal.isSettled(h) && internal.inFlight.indexOf(h) === -1)
      if (wanted.length === 0) return
      internal.inFlight = wanted.slice(0, internal.maxBatch)
      process.run(internal.inFlight)
    }

    // Every in-flight handle is settled, as "" on any failure, so a batch
    // always terminates and is never re-requested.
    function cacheBatch(parsed) {
      const fetched = Object.create(null)
      internal.inFlight.forEach(h => {
        const uri = parsed && Object.prototype.hasOwnProperty.call(parsed, h) ? parsed[h] : ""
        fetched[h] = typeof uri === "string" ? uri : ""
      })
      // Bound the cache: once over the cap, keep only this round's avatars.
      const merged = Object.assign(Object.create(null), internal.cache, fetched)
      internal.cache = Object.keys(merged).length > internal.maxAvatars ? fetched : merged
      root.settled()
      internal.inFlight = []
      internal.fetchNextBatch()
    }
  }

  HelperProcess {
    id: process
    helper: "fetch-avatars"
    // Defence in depth on the helper's own batch cap: bound the parse cost.
    maxStdoutBytes: 4 * 1024 * 1024
    onSucceeded: (stdout) => {
      let parsed = null
      try { parsed = JSON.parse(stdout) } catch (e) { /* parsed stays null */ }
      internal.cacheBatch(parsed && typeof parsed === "object" ? parsed : null)
    }
    onFailed: internal.cacheBatch(null)
  }
}
