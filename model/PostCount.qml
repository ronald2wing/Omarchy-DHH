pragma ComponentBehavior: Bound
import QtQuick

// DHH's live number of X posts, fetched once per process through helpers/fetch-post-count.
Item {
  id: root

  // Bound to the panel's open state. Closing cancels a fetch in flight; a
  // canceled fetch is not retried, as the count is only decoration.
  property bool active: false
  // The fetched count, or the fallback until a fetch succeeds.
  readonly property int count: internal.count

  onActiveChanged: root.active ? internal.fetch() : process.cancel()
  Component.onCompleted: { if (root.active) internal.fetch() }

  QtObject {
    id: internal
    // The count x.com showed on DHH's profile (72.2K) when the plugin was
    // started, in August 2026: shown offline and until the first fetch.
    readonly property int fallbackCount: 72200
    property int count: internal.fallbackCount
    property bool requested: false

    function fetch() {
      if (internal.requested) return
      internal.requested = true
      process.run([])
    }
  }

  HelperProcess {
    id: process
    helper: "fetch-post-count"
    // One integer line; anything longer is not a count.
    maxStdoutBytes: 64
    onSucceeded: (stdout) => {
      // Anything but one non-negative integer that fits an int keeps the
      // current count.
      const text = stdout.trim()
      if (!/^[0-9]+$/.test(text)) return
      const n = parseInt(text, 10)
      if (n > 2147483647) return
      internal.count = n
    }
  }
}
