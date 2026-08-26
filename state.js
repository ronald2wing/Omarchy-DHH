// Shared DHH persisted-state helpers. Locale- and Qt-free so they load via
// `import "state.js" as State` in QML and `vm` in node tests. Callers pass the
// raw text / list explicitly, so nothing here reaches back into QML state.

// Parse `raw` into an array; returns null on bad JSON or a non-array value.
function parseJsonArray(raw) {
  try {
    const parsed = JSON.parse(String(raw || ""))
    return Array.isArray(parsed) ? parsed : null
  } catch (e) { return null }
}

// `list` minus any case-insensitive match for `query` (trimmed).
function recentSearchesExcluding(list, query) {
  const lower = String(query || "").trim().toLowerCase()
  return (list || []).slice().filter(e => String(e).toLowerCase() !== lower)
}

// Build the dataset lookup indexes from `raw` (JSON Lines) and return them as a
// local `{ byId, bySource, byText }`. A missing or empty dataset yields empty
// indexes, so resolveEntry falls back to the stored snapshot. Malformed lines
// are skipped. The maps are local: they are needed only for the one-time
// history reconciliation at startup, so they are never retained beyond that
// pass.
function buildDatasetLookup(raw) {
  const byId = Object.create(null)
  const bySource = Object.create(null)
  const byText = Object.create(null)
  const lines = String(raw || "").split("\n")
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim()
    if (line === "") continue
    try {
      const e = JSON.parse(line)
      if (!e || typeof e !== "object") continue
      if (e.id) byId[e.id] = e
      if (e.source) bySource[e.source] = e
      if (e.text) byText[e.text] = e
    } catch (err) { /* skip malformed line */ }
  }
  return { byId: byId, bySource: bySource, byText: byText }
}

// Resolve a persisted history snapshot against the current dataset so the
// history reflects the live entry (id, context.verified, a corrected source,
// ...). Match priority: id -> source -> text. No match returns the stored
// snapshot unchanged.
function resolveEntry(stored, lookup) {
  if (!stored || typeof stored !== "object") return stored
  if (stored.id && lookup.byId[stored.id]) return lookup.byId[stored.id]
  if (stored.source && lookup.bySource[stored.source]) return lookup.bySource[stored.source]
  if (stored.text && lookup.byText[stored.text]) return lookup.byText[stored.text]
  return stored
}
