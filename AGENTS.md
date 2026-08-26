# AGENTS.md

Omarchy (Quickshell) bar-widget plugin: search DHH quotes and X posts, copy
text, or render a shareable image. The dataset is bundled and works offline,
but the plugin makes two lightweight network fetches at runtime, each with an
offline fallback: DHH's avatar is bundled directly as `data/avatar-x.png` (pre-cropped circular RGBA, no live fetch needed);
reply/repost quoted-card author avatars
(`https://unavatar.io/x/<handle>` → bundled `data/avatar-default.png`); and the
live post count (`https://api.fxtwitter.com/2/profile/dhh` → `"72.2K posts"`).

## The #1 gotcha: working copy ≠ installed copy

**Always restart after plugin changes.** Every change to plugin files (QML/JS/data/bin/manifest) must be followed by `cp <changed files> ~/.config/omarchy/plugins/dhh/` and `omarchy restart shell` (retry once if it reports "not responding") before reporting the change as working.

The repo at `~/Desktop/Omarchy/DHH/` is the source. The running plugin lives at
`~/.config/omarchy/plugins/dhh/`. Editing the repo does nothing until you sync
and restart:

```sh
cp <changed files> ~/.config/omarchy/plugins/dhh/
omarchy restart shell && omarchy-shell dhh open
```

`omarchy restart shell` may transiently report "not responding" — retry the
`open` once. quickshell logs: `/run/user/1000/quickshell/by-id/<id>/log.log`.

## Architecture

- `BarWidget.qml` — bar entry point (glyph button + IPC). Loads `Panel.qml` via
  a `Loader` and injects `bar`/`anchorItem`/`hostWidget`/`service` into it.
- `Panel.qml` — the whole UI: search field, X-style result rows (author line
  with avatar + name + verified badge + 37signals logo + `@dhh · <relative
  time>`, then body/quote and an engagement/action row), copy-text and
  render-image actions, keyboard nav, and the render preview. While a render is
  in flight the image button dims (`renderingText` compare); render failures
  surface via toasts ("Render failed" / "Render timed out"); a successful render
  shows the preview with an inline "Saved · Copied to clipboard" status line.
- `Service.qml` — shared state: parsed dataset (loaded eagerly at bar startup),
  render state (`generating`, `renderPathDelivered`), recent-query list, and copy
  history.
- `search.js` — Qt-free search + slug helpers. Imported `as Search` by both
  `Service.qml` and `Panel.qml`, `Qt.include`d in `SearchWorker.js`, and loaded
  via `vm` in `tests/test_search.js` and `bin/omarchy-dhh-render`. It exports
  `normalize` and `entryId` (the shared id rule) used by the render
  script, `bin/omarchy-add-entry`, and `tests/test_data.js`. It must stay Qt-free
  and must NOT contain `.pragma`/`.import` directives.
- `format.js` — Qt-free formatting helpers (`escapeHtml`/`formatDate`/`formatCount`/
  `formatPosts`/`engagementCounts`/`_hash32`), imported `as Fmt` in `Panel.qml`
  and loaded via
  `vm` in `bin/omarchy-dhh-render` + `tests/test_format.js`. Same contract as
  `search.js`: no `.pragma`/`.import`/`module.exports`.
- `SearchWorker.js` — WorkerScript wrapper; caches the entries array in its
  global scope after the first message so later searches send only the query.
- `bin/shared.js` — CommonJS helpers: `sha256Hex` and `loadScript` (vm sandbox
  loader), consumed by the render script, add-entry, and all test files.
- `bin/omarchy-add-entry` — append helper that computes the content-derived
  `id` and prints one JSONL line to stdout.
- `bin/omarchy-dhh-render` — node subprocess that builds the HTML template,
  renders with chromium headless, writes the PNG to `~/Pictures/dhh/`, and
  copies it to the clipboard with `wl-copy --type image/png`.
- `data/quotes.jsonl` — JSON Lines dataset (one entry per line, append-only).
- `data/avatar-x.png` — DHH's color photo pre-cropped to circular with alpha, used by the panel result rows as a plain `Image` (no mask needed) and by the render script as a data URI. `data/avatar.png` — the grayscale version, faded into the classic quote-card render.

## Data model

Each line of `data/quotes.jsonl`: `{ id, type, text, source, date?, kind?,
context?, title?, domain? }`. `id` is the first 8 hex
chars of the SHA-256 of `normalize(text)`
(`String(text).trim().toLowerCase().replace(/\s+/g, " ")`) — content-derived, so
a given text always yields the same id. `type` is one of `"post"`, `"quote"`,
`"link"`, or `"video"`. `date` is optional (`YYYY-MM-DD`); when omitted the
rendered image omits the timestamp line.

The top-level card style is chosen by `isQuote` (type + source): quotes from
x.com/twitter.com sources, posts, videos, and reply/repost entries render as
X-post cards; quotes from other sources and links render as the classic
grayscale card. `kind` discriminates the quoted-card body, present only
together with `context` (which carries `{ author, handle, text?, date? }` — the
original post being answered or reposted):

- `kind: "reply"` — `text` is DHH's reply; the original post lives in `context`.
  Renders DHH's body, then the original post as a bordered quoted card (with the
  original author's avatar, name, handle, and time), with no separate
  "Replying to" line.
- `kind: "repost"` — renders DHH's body plus the quoted card, with NO replying-to
  line. The quoted card shows `context.text` when present.

`text` is DHH's own words in every entry EXCEPT the single bare repost (id
`1d7ae346`, Chad Fowler): there `text` holds the other person's words and
`context.text` is omitted, so the renderer falls back to `text` for the quoted
card. `id` = `sha256(normalize(text)).slice(0,8)` is computed over DHH's words
(over the stored `text`, which for that one bare repost is the other person's
words). `link` entries flatten `title`/`domain`. Plain `post`/`link`/`video`
entries carry no `kind`/`context`. Search matches the original post's `context`
text, author, and handle too.

`bin/omarchy-add-entry` is the append helper: `bin/omarchy-add-entry --type
<post|quote|link|video> --text "<...>" --source "<url>" [--date <YYYY-MM-DD>]`
computes `id` and prints one JSONL line to stdout (built on `process.argv` + a
`require("../bin/shared")` import for `sha256Hex` and `vm`-based `loadScript` of
`search.js` for the shared `normalize`/`entryId` id rule). For posts, `--kind
reply|repost --context-author "<name>"
--context-handle "@handle"` tags the original post (optionally `--context-text
"<...>" --context-date <YYYY-MM-DD>`); for links,
`--title "<title>" --domain "<domain>"`.
`tests/test_data.js` validates the file against a per-type schema registry — a
`type → {required, optional}` map.

## Verification (run before claiming anything works)

```sh
qmllint -I "$OMARCHY_PATH/shell" Panel.qml Service.qml   # BarWidget.qml exits 255 — known Quickshell tooling limitation, not a regression
node tests/test_search.js    # search.js helpers
node tests/test_format.js    # format.js helpers
node tests/test_data.js      # validates data/quotes.jsonl structure
node --check search.js SearchWorker.js bin/shared.js bin/omarchy-dhh-render bin/omarchy-add-entry
```

## Conventions

- **Component-local names** are already scoped by file; use descriptive names
  (e.g. `copyEntry`, `renderEntryAt`).
- **Library files** (`search.js`, `format.js`) mark module-private helpers with a
  leading `_` (`_textMatchesQuery`, `_hash32`). `Panel.qml` does not use the `_`
  prefix.
- **Copy-to-clipboard** uses `copyToClipboard(text)` helper; the format is
  type-aware (`copyEntry`). For `post`/`quote`/`video` entries the clipboard
  carries the text followed by `— David Heinemeier Hansson (@dhh)` and the bare
  URL (URL omitted when there is no source; no `Source: ` prefix). For `link`
  entries it carries the title/domain/URL (whichever is present, newline-joined)
  followed by the commentary text. Feedback strings do not carry the
  attribution.
- **No new dependencies** without explicit user justification. The image
  pipeline invokes `chromium` (`/usr/bin/chromium`), `wl-copy`, and
  `/usr/bin/magick`; the panel also calls `xdg-open` (open the output folder),
  `bash`/`printf` (text copy), and `mkdir` (state-dir creation).
- **Terminology**: the platform is X, NOT Twitter. Never use
  "tweet"/"tweeter"/"tweeted" in identifiers, comments, UI strings, docs, or
  filenames. Use "X post" / "post".
- **No emoji** in code or comments.

## Gotchas

- `Panel.qml` `onTextChanged` handlers must reference the TextField's own `text`
  property, not a component-internal id (a ReferenceError silently kills the
  search trigger).
- The search worker has a stale-response guard (`msg.query !== root.query`);
  preserve it.
- `highlightQuery` uses RichText; the result body calls it.
- Render entry is passed via argv — `renderProcess.exec([root.renderScriptPath,
  JSON.stringify(entry)])`. Do NOT write it to stdin (Process.write is a no-op
  before the process is running). The panel clears `service.generating` in
  `onExited`.
