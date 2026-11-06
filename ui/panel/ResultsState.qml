pragma ComponentBehavior: Bound
import QtQuick
import "../../model"
import "../../js/search-status.mjs" as SearchStatus

// The results' state: debounced search, response landing, status, suggestions, no-results filler.
Item {
  id: resultsState

  required property Dataset dataset
  required property RecentSearches recentSearches
  required property AvatarCache avatars
  // The result cap passed to the worker (a capped scan reads "<cap>+
  // results"), and the size of the no-results filler.
  required property int pageSize
  // The query as typed.
  required property string query

  readonly property bool hasQuery: resultsState.query.trim() !== ""
  readonly property ListModel model: ListModel {}
  // True once a search has answered (or is waiting on the dataset) and until
  // the query clears. The feed stays up until then: swapping it for the
  // empty state on the first keystroke made the panel collapse and then grow
  // back when the results landed.
  readonly property bool shown: internal.shown
  readonly property string statusText: internal.statusText
  readonly property var suggestions: internal.suggestions

  // The rows were replaced, by a response or by the no-results filler.
  signal replaced()

  // Search for the query once it has sat for the debounce interval, and
  // remember it once it has sat for longer.
  function schedule() {
    debounce.restart()
    rememberTimer.restart()
  }

  function cancelRemember() {
    rememberTimer.stop()
  }

  QtObject {
    id: internal
    // The tag of the filler's draw. It names the query, so a filler drawn for
    // a superseded query is ignored.
    readonly property string drawTag: "results:" + resultsState.query
    property bool shown: false
    property string statusText: ""
    property var suggestions: []

    // The previous rows stay on screen until the new ones land: clearing
    // them first would collapse the panel to the empty state and rebuild
    // every card on each keystroke, which is what makes typing feel
    // sluggish.
    function run() {
      internal.suggestions = []
      if (!resultsState.hasQuery) {
        lander.clear()
        internal.shown = false
        internal.statusText = ""
        return
      }
      if (!resultsState.dataset.ready) {
        internal.statusText = SearchStatus.LOADING_TEXT
        internal.shown = true
        return
      }
      internal.statusText = SearchStatus.SEARCHING_TEXT
      resultsState.dataset.search(resultsState.query, resultsState.pageSize)
    }

    // describeResponse picks the status text, the highlight query and
    // whether filler is needed.
    function show(response) {
      const status = SearchStatus.describeResponse(response, resultsState.query, resultsState.pageSize)
      internal.shown = true
      lander.replace(response.results || [], status.highlightQuery)
      internal.statusText = status.text
      if (status.needsFiller) resultsState.dataset.draw(resultsState.pageSize, [], internal.drawTag)
      internal.suggestions = response.suggestions || []
      resultsState.replaced()
    }

    // Random posts standing in for an empty result set. Unhighlighted:
    // nothing in them matches.
    function showFiller(entries) {
      if (!resultsState.hasQuery || !internal.shown) return
      lander.replace(entries)
      resultsState.replaced()
    }
  }

  // The rows above the fold land at once, the rest a few per tick, and a
  // newer response simply takes over the queue: rebinding every row at once
  // still stalls for a few frames.
  RowLander {
    id: lander
    model: resultsState.model
    avatars: resultsState.avatars
    rowsAtOnce: 8
    rowsPerTick: 4
  }

  Timer {
    id: debounce
    interval: 80
    onTriggered: internal.run()
  }

  // A query counts as a recent search once it has sat unchanged for 3 s.
  Timer {
    id: rememberTimer
    interval: 3000
    onTriggered: resultsState.recentSearches.remember(resultsState.query)
  }

  Connections {
    target: resultsState.dataset
    function onSearched(response) { if (response.query === resultsState.query) internal.show(response) }
    function onDrawn(entries, tag) { if (tag === internal.drawTag) internal.showFiller(entries) }
    function onReadyChanged() { if (resultsState.dataset.ready && resultsState.hasQuery) internal.run() }
  }
}
