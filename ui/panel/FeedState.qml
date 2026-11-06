pragma ComponentBehavior: Bound
import QtQuick
import "../../model"
import "../../js/entries.mjs" as Entries

// The feed's state: history first, then random posts drawn a page at a time.
Item {
  id: feedState

  required property Dataset dataset
  required property History history
  required property AvatarCache avatars
  // Posts per draw.
  required property int pageSize
  // The feed is active: the panel is open and the query is empty (the list
  // can stay shown until the results replace it). Turning true rebuilds the
  // feed from history; turning false stops the landing, and the next rebuild
  // starts over, so nothing pending is lost.
  required property bool active
  // The body is scrolling; landing rows wait for it to settle.
  property bool scrolling: false
  // The viewport's bottom is within preload distance of the feed's end.
  property bool nearEnd: false

  readonly property ListModel model: ListModel {}

  onActiveChanged: feedState.active ? internal.rebuild() : lander.cancel()
  onNearEndChanged: internal.requestPageIfNearEnd()
  Component.onCompleted: { if (feedState.active) internal.rebuild() }

  QtObject {
    id: internal
    // The tag of the feed's draws, so the feed takes only its own draws.
    readonly property string drawTag: "feed"
    property bool pageRequested: false
    // The content key of every row the feed holds or is landing, history
    // included: the draws exclude them, so the feed never repeats a post.
    property var heldKeys: Object.create(null)

    // Ask for the next page while the feed is active, nothing is in flight,
    // and the previous page has landed, so the queue stays bounded.
    function requestPage() {
      if (!feedState.active || internal.pageRequested || lander.landing || !feedState.dataset.ready) return
      internal.pageRequested = true
      feedState.dataset.draw(feedState.pageSize, Object.keys(internal.heldKeys), internal.drawTag)
    }

    // Only while active: a closed panel never lays the feed out, so its end
    // would stay "near" and every landed page would request the next one
    // indefinitely.
    function requestPageIfNearEnd() {
      if (!feedState.active || !feedState.nearEnd || feedState.model.count === 0) return
      internal.requestPage()
    }

    // Bring the feed's head in line with history without rebuilding it: a
    // copied or rendered row moves up into its history slot (its card, and
    // the "Copied" tip it is showing, survive), an entry the feed never
    // showed is inserted. The rows below keep their place, so the scroll
    // does not jump.
    function syncHistory() {
      const entries = feedState.history.entries
      for (let i = 0; i < entries.length; i++) {
        const key = Entries.contentKey(entries[i])
        let at = -1
        for (let j = 0; j < feedState.model.count; j++) {
          if (Entries.contentKey(feedState.model.get(j).entry) === key) { at = j; break }
        }
        if (at === -1) {
          feedState.model.insert(i, lander.makeRow(entries[i]))
          internal.heldKeys[key] = true
          // A row still waiting to land must not land as a duplicate.
          lander.discard(entry => Entries.contentKey(entry) === key)
        } else if (at !== i) {
          feedState.model.move(at, i, 1)
        }
      }
    }

    // Rebuild the feed from history and start streaming random posts. The
    // history's avatars are requested on every open
    // (AvatarCache.requestOnOpen).
    function rebuild() {
      lander.clear()
      internal.heldKeys = Object.create(null)
      const entries = feedState.history.entries
      entries.forEach(entry => { internal.heldKeys[Entries.contentKey(entry)] = true })
      if (entries.length > 0) feedState.model.append(entries.map(entry => lander.makeRow(entry)))
      internal.requestPage()
    }

    function acceptPage(entries) {
      internal.pageRequested = false
      if (!feedState.active) return
      // The worker already skipped the excluded keys; re-check in case the
      // feed moved on while the response was in flight.
      const fresh = entries.filter(entry => {
        const key = Entries.contentKey(entry)
        if (internal.heldKeys[key]) return false
        internal.heldKeys[key] = true
        return true
      })
      if (fresh.length > 0) {
        lander.append(fresh)
        return
      }
      // Nothing lands, so no drained signal asks for the next page: ask now,
      // unless the draw came back empty (its random picks all hit held keys,
      // or the dataset is exhausted).
      if (entries.length > 0) internal.requestPageIfNearEnd()
    }
  }

  // One row per tick, and none while the body moves: appended rows are what
  // drops frames under a flick.
  RowLander {
    id: lander
    model: feedState.model
    avatars: feedState.avatars
    paused: feedState.scrolling
    // A page that landed while the viewport sat near the end starts the
    // next request at once.
    onDrained: internal.requestPageIfNearEnd()
  }

  Connections {
    target: feedState.dataset
    function onDrawn(entries, tag) { if (tag === internal.drawTag) internal.acceptPage(entries) }
    // The history rows are already up; the dataset arriving only unblocks
    // the random stream behind them.
    function onReadyChanged() { if (feedState.dataset.ready) internal.requestPage() }
  }

  Connections {
    target: feedState.history
    function onEntriesChanged() { if (feedState.active) internal.syncHistory() }
  }
}
