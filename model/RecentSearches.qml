pragma ComponentBehavior: Bound
import QtQuick

// Past queries, most recent first, persisted in ~/.local/state/dhh/recent.json.
PersistedList {
  fileName: "recent.json"
  maxItems: 6
  // Queries are kept trimmed, and two differing only in case are one.
  clean: query => String(query || "").trim() || null
  keyOf: query => query.toLowerCase()

  readonly property var queries: items
}
