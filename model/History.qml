pragma ComponentBehavior: Bound
import QtQuick
import "../js/entries.mjs" as Entries

// The copied and rendered entries, most recent first, persisted in ~/.local/state/dhh/history.json.
PersistedList {
  id: root

  required property Dataset dataset
  readonly property var entries: items

  fileName: "history.json"
  maxItems: 20
  // Two copies of the same content are one entry; an entry without text is
  // dropped.
  keyOf: Entries.contentKey
  clean: entry => entry && typeof entry === "object" && String(entry.text || "").trim() !== "" ? entry : null

  // Stored entries show as loaded right away. Once the dataset is ready they
  // are refreshed against it, so an entry edited since it was stored shows
  // its current text.
  onLoaded: {
    internal.stored = root.entries
    internal.refreshStored()
  }

  QtObject {
    id: internal
    // The entries as loaded, until the dataset's refreshed answer replaces
    // them; null before the load and after the refresh.
    property var stored: null

    // Ask once both the stored entries and the dataset are in hand: the
    // load and the dataset's readiness each happen once, so this asks once.
    function refreshStored() {
      if (internal.stored === null || !root.dataset.ready) return
      if (internal.stored.length === 0) { internal.stored = null; return }
      root.dataset.refresh(internal.stored)
    }

    // Replace each stored entry with its refreshed version (the dataset
    // answers in the order it was asked). Entries remembered since the load
    // keep their place at the head.
    function merge(stored, refreshed) {
      const replacement = Object.create(null)
      for (let i = 0; i < stored.length && i < refreshed.length; i++) {
        replacement[Entries.contentKey(stored[i])] = refreshed[i]
      }
      return root.entries.map(e => replacement[Entries.contentKey(e)] || e)
    }
  }

  Connections {
    target: root.dataset
    function onReadyChanged() { internal.refreshStored() }
    function onRefreshed(refreshed) {
      if (internal.stored === null) return
      const stored = internal.stored
      internal.stored = null
      // Saved only when the text differs, so an up-to-date file is not
      // rewritten on every load while a stale one self-heals.
      root.replaceAll(internal.merge(stored, refreshed))
    }
  }
}
