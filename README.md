# DHH for Omarchy

An [Omarchy](https://omarchy.org) (Quickshell) bar-widget plugin that searches
David Heinemeier Hansson's (@dhh) public quotes and X posts from a bundled
dataset. A glyph sits in the bar; left-clicking it toggles a search panel where
you can:

- **Copy the text** of a quote or X post to the clipboard; see Usage below for
  the exact format.
- **Render an image** of the quote or X post (via chromium headless) and save it
  to `~/Pictures/dhh/` and copy it to the clipboard.

Plugin id: `dhh`

## Install

```sh
omarchy plugin add https://github.com/ronald2wing/Omarchy-DHH --enable
```

## Usage

- **Click** a result to copy the text to the clipboard, followed by the
  attribution line and source URL (format defined in `Panel.qml`). For `link`
  entries the copy is the title/domain/URL (whichever is present) followed by
  the commentary text, then the attribution line.
- Click the **share-arrow icon** to render the entry as a PNG, save it to
  `~/Pictures/dhh/<slug>-<id>.png`, and copy it to the clipboard. The rendered
  image is shown as a full-width **preview** below the search field, with a
  folder button to open the output directory. x.com/twitter.com posts, videos,
  quotes, and reply/repost/quote entries render as X-post cards while other
  quote and link entries render as the classic grayscale card; see
  [CONTRIBUTING.md](CONTRIBUTING.md) for the routing rules.
- Click the **Grok-mark button** to render a random entry.
- Focusing the empty search field opens a **recent searches** dropdown; typing
  opens a **word-autocomplete** dropdown with **Trending** suggestions.
- The **History** section lists entries you have copied or rendered while the
  query is empty.
- Type to search (substring match, debounced). `↑`/`↓` move the selection,
  `Enter` copies the selected entry's text, `Esc` closes the panel.
- `Tab` / `Shift+Tab` switches to the neighbouring bar panel.

## Data and privacy

- The dataset lives in `data/quotes.jsonl` (JSON Lines, one entry per line).
  The entry schema, `type`/`kind`/`context` semantics, text ownership, the
  `verified` badge fields, the sort invariant, and the
  `bin/omarchy-add-entry` / `bin/omarchy-fetch-posts` workflows are documented
  in [CONTRIBUTING.md](CONTRIBUTING.md), the authoritative reference.
- `data/avatar-x.png` is DHH's color photo pre-cropped to circular with alpha,
  bundled directly (no network fetch); it is used by the panel result rows as a
  plain `Image` (no mask needed) and by the render script as a data URI.
  `data/avatar.png` is the grayscale version, faded into the classic quote-card
  render. `data/avatar-mask.png` is the white-disc mask that
  `components/CircularAvatar.qml` applies to render result-row avatars —
  including the `data/avatar-default.png` fallback — as circles.
- Rendered images go to `~/Pictures/dhh/`; the plugin writes only two small
  state files under `~/.local/state/dhh/` — `recent.json` (recent searches) and
  `history.json` (entries you have copied or rendered).
- Does not request elevated privileges, runs no background services, and starts
  no second Quickshell process.

## Runtime dependencies

At runtime the plugin uses only tools that ship with default Omarchy: `ruby`
(the `bin/` scripts), `chromium` (headless, for image rendering),
`/usr/bin/magick` (ImageMagick, to crop the rendered canvas), `wl-copy`
(wl-clipboard, for clipboard writes), `xdg-open` (xdg-utils, open the output
folder), and `mkdir` (state-directory creation). Text copy uses Quickshell's
native clipboard API, so no external tool is needed for text.
No Node.js is required at runtime.

## Network access

The plugin makes two lightweight network fetches at runtime, each with an
offline fallback:

- **Reply/repost quoted-card author avatars** — `https://unavatar.io/x/<handle>`
  (handle without the leading `@`), falling back to the bundled
  `data/avatar-default.png`.
- **Live post count** — `https://api.fxtwitter.com/2/profile/dhh` (JSON
  `user.statuses`), falling back to the `postCount` default in `Service.qml`.

Everything else is bundled and works offline.

## Development checks

```sh
omarchy plugin validate .
ruby -c bin/omarchy-dhh-render bin/omarchy-add-entry bin/omarchy-fetch-posts bin/omarchy-sort-data bin/dhh_helpers.rb
ruby tests/test_data.rb
ruby tests/test_helpers.rb
node tests/test_search.js
node tests/test_format.js
node tests/test_state.js
node --check search.js SearchWorker.js format.js state.js tests/load_script.js
/usr/lib/qt6/bin/qmllint -I "$OMARCHY_PATH/shell" Panel.qml Service.qml
```

Note: `qmllint` on `PATH` is Qt 5 and exits 255 on the
`pragma ComponentBehavior: Bound` line; use `/usr/lib/qt6/bin/qmllint`.

## Remove

```sh
omarchy plugin remove dhh
```

## License

UNLICENSED (all rights reserved); see the `LICENSE` file at the repo root. The
bundled quotes and X posts are public statements by David Heinemeier Hansson,
each linked to its source; the avatar is DHH's public photo. See
[CONTRIBUTING.md](CONTRIBUTING.md) for the contribution rules.
