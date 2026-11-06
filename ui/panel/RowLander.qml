pragma ComponentBehavior: Bound
import QtQuick
import "../../model"
import "../../js/entries.mjs" as Entries
import "../../js/highlight.mjs" as Highlight

// Feeds post rows into a ListModel a few per 16 ms frame, replacing the model's rows or appending to them.
// It takes whole pages and requests their context avatars itself: AvatarCache.request replaces the queue
// not yet in flight, so a request must cover a page, made before its rows land, never a row at a time.
Item {
  id: lander

  required property ListModel model
  required property AvatarCache avatars
  property int rowsPerTick: 1
  property int rowsAtOnce: lander.rowsPerTick
  // While true, ticks land nothing: the rows wait for a scroll to settle
  // rather than compete with it for the frame.
  property bool paused: false
  // True while rows are waiting to land.
  readonly property bool landing: internal.next < internal.rows.length

  // The queue emptied: every row handed to replace() or append() is in the model.
  signal drained()

  // One model row: the entry plus its body HTML with `highlightQuery`
  // highlighted ("" for none).
  function makeRow(entry, highlightQuery = "") {
    return { entry: entry, bodyHtml: Highlight.highlightHtml(Entries.postBody(entry), highlightQuery) }
  }

  // Replace the model's rows with `entries`: `rowsAtOnce` at once (the rows
  // above the fold), then `rowsPerTick` per tick. A card costs most of a
  // frame to build, so a whole batch at once would stall the GUI thread for
  // several frames.
  // Rows the model already has are overwritten in place so their cards
  // rebind instead of being rebuilt, a row that did not change is left
  // alone, and the surplus tail goes at once.
  function replace(entries, highlightQuery = "") {
    lander.avatars.request(entries)
    const rows = entries.map(entry => lander.makeRow(entry, highlightQuery))
    internal.replacing = true
    internal.rows = rows
    internal.next = 0
    if (lander.model.count > rows.length) lander.model.remove(rows.length, lander.model.count - rows.length)
    internal.step(lander.rowsAtOnce)
    timer.running = lander.landing
    if (!lander.landing) lander.drained()
  }

  // Queue `entries` after the model's end, `rowsPerTick` per tick.
  function append(entries) {
    lander.avatars.request(entries)
    if (internal.replacing) lander.cancel()
    internal.rows = internal.rows.slice(internal.next).concat(entries.map(entry => lander.makeRow(entry)))
    internal.next = 0
    timer.running = lander.landing
  }

  // Drop every row not landed yet whose entry `matches`.
  function discard(matches) {
    const rows = internal.rows
    internal.rows = rows.slice(0, internal.next).concat(rows.slice(internal.next).filter(row => !matches(row.entry)))
  }

  // Drop the rows not landed yet; the model keeps what it has.
  function cancel() {
    timer.stop()
    internal.replacing = false
    internal.rows = []
    internal.next = 0
  }

  // Drop the rows not landed yet and empty the model.
  function clear() {
    lander.cancel()
    lander.model.clear()
  }

  QtObject {
    id: internal
    property bool replacing: false
    property var rows: []
    property int next: 0

    // Land up to `limit` more rows.
    function step(limit) {
      const end = Math.min(internal.rows.length, internal.next + limit)
      if (!internal.replacing) {
        if (end > internal.next) lander.model.append(internal.rows.slice(internal.next, end))
        internal.next = end
        return
      }
      const fresh = []
      for (let i = internal.next; i < end; i++) {
        const row = internal.rows[i]
        if (i >= lander.model.count) { fresh.push(row); continue }
        const current = lander.model.get(i)
        if (current.bodyHtml === row.bodyHtml && Entries.contentKey(current.entry) === Entries.contentKey(row.entry)) continue
        lander.model.set(i, row)
      }
      if (fresh.length > 0) lander.model.append(fresh)
      internal.next = end
    }
  }

  Timer {
    id: timer
    interval: 16
    repeat: true
    onTriggered: {
      if (lander.paused) return
      internal.step(lander.rowsPerTick)
      if (lander.landing) return
      timer.stop()
      lander.drained()
    }
  }
}
