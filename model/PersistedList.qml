pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

// A capped, deduplicated, most-recent-first list kept as a JSON array in ~/.local/state/dhh/<fileName>.
Item {
  id: root

  required property string fileName
  required property int maxItems
  // What two duplicates share; given cleaned items.
  property var keyOf: item => item
  // An item as kept, or null (or undefined) to drop it. Applied on load and
  // on every change, so the list holds only cleaned items.
  property var clean: item => item
  // Most recent first: cleaned, one per key, at most maxItems.
  readonly property var items: internal.items

  // The file has been read; a missing, unreadable or non-array file reads as
  // an empty list. Loading never writes: a file is rewritten only by a change.
  signal loaded()

  // Put an item at the head, dropping an older duplicate.
  function remember(item) {
    const cleaned = root.clean(item)
    if (cleaned == null) return
    internal.update([cleaned].concat(internal.items))
  }

  function forget(item) {
    const cleaned = root.clean(item)
    if (cleaned == null) return
    const key = root.keyOf(cleaned)
    internal.update(internal.items.filter(i => root.keyOf(i) !== key))
  }

  function clear() {
    internal.update([])
  }

  function replaceAll(items) {
    internal.update(items)
  }

  QtObject {
    id: internal
    // The one home of the state path. Kept as is for existing users: no
    // XDG_STATE_HOME, no migration.
    readonly property string directory: Quickshell.env("HOME") + "/.local/state/dhh"
    property var items: []
    // The file's text as last loaded or saved; null when unknown (after a
    // failed save), so the next save writes.
    property var lastText: null

    // The cleaned items of `list`, first of each key, at most maxItems.
    function normalized(list) {
      const seen = Object.create(null)
      const out = []
      for (let i = 0; i < list.length && out.length < root.maxItems; i++) {
        const item = root.clean(list[i])
        if (item == null) continue
        const key = root.keyOf(item)
        if (seen[key]) continue
        seen[key] = true
        out.push(item)
      }
      return out
    }

    function update(list) {
      internal.items = internal.normalized(list)
      internal.save()
    }

    // Writes only when the serialized list differs from the text last loaded
    // or saved, so every change can call it.
    function save() {
      const text = JSON.stringify(internal.items) + "\n"
      if (text === internal.lastText) return
      internal.lastText = text
      file.setText(text)
    }

    // A persisted JSON array; bad JSON or a non-array yields [].
    function parseArray(raw) {
      try {
        const parsed = JSON.parse(String(raw || ""))
        return Array.isArray(parsed) ? parsed : []
      } catch (e) { return [] }
    }
  }

  // Loads as soon as the list exists (with the bar, not the panel), so
  // persisted state is up before the first open. Written atomically; a save
  // creates the missing directories itself (Quickshell 0.3.2's FileView).
  FileView {
    id: file
    path: internal.directory + "/" + root.fileName
    atomicWrites: true
    printErrors: false
    onLoaded: {
      const text = file.text()
      internal.lastText = text
      internal.items = internal.normalized(internal.parseArray(text))
      root.loaded()
    }
    onLoadFailed: root.loaded()
    // What is on disk is unknown now, so the next change writes.
    onSaveFailed: internal.lastText = null
  }
}
