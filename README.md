# DHH for Omarchy

An [Omarchy](https://omarchy.org) (Quickshell) bar-widget plugin that searches
David Heinemeier Hansson's (@dhh) public quotes and X posts from a bundled,
curated dataset. A glyph sits in the bar; left-clicking it toggles a search
panel where you can:

- **Copy the text** of a quote or X post to the clipboard (followed by `— David
  Heinemeier Hansson (@dhh)` and the bare source URL).
- **Render an image** of the quote or X post (via chromium headless) and save it
  to `~/Pictures/dhh/` and copy it to the clipboard.

Plugin id: `dhh`

## Install

```sh
omarchy plugin add https://github.com/ronald2wing/Omarchy-DHH --enable
```

The plugin makes two lightweight network fetches at runtime, each with an
offline fallback:

- **DHH's avatar** — bundled directly as `data/avatar-x.png` (pre-cropped circular
  RGBA, no live fetch needed).
- **Reply/repost quoted-card author avatars** — `https://unavatar.io/x/<handle>`
  (handle sans leading `@`), falling back to the bundled `data/avatar-default.png`.
- **Live post count** — `https://api.fxtwitter.com/2/profile/dhh` (JSON
  `user.statuses`), falling back to `"72.2K posts"`.

Everything else is bundled and works offline. The image pipeline invokes
`chromium` (headless, for image rendering), `/usr/bin/magick` (to crop the
rendered canvas), and `wl-copy` (for clipboard writes); the panel also calls
`xdg-open` (open the output folder), `bash`/`printf` (text copy), and `mkdir`
(create the state directory). All are already installed on the target system.

## Usage

- **Click** a result to copy its text. Copies carry the text followed by `—
  David Heinemeier Hansson (@dhh)` and the bare source URL. For `link` entries
  the copy is the title/domain/URL (whichever is present) followed by the
  commentary text.
- Click the **share-arrow icon (render)** on a result to render the quote/post as a PNG, save
  it to `~/Pictures/dhh/<slug>-<id>.png`, and copy the PNG to the clipboard. The
  rendered image is shown as a full-width **preview** below the search field,
  with a folder button to open the output directory. Quotes from x.com/twitter.com
  sources, posts, videos, and reply/repost entries render as X-post cards; quotes
  from other sources and links render as the classic grayscale card.
- Click the **Grok-mark button** in the header to render a random entry's image.
- Focusing the empty search field opens a **recent searches** dropdown; typing
  opens a **word-autocomplete** dropdown with **Trending** suggestions.
- The **History** section lists previously copied entries while the query is
  empty.
- Type to search (substring match, debounced). `↑`/`↓` move the selection,
  `Enter` copies the selected entry's text, `Esc` closes the panel.
- `Tab` / `Shift+Tab` switches to the neighbouring bar panel.

## Data and privacy

- The dataset lives in `data/quotes.jsonl` (JSON Lines, one entry per line).
  Each entry is `{ id, type, text, source, date?, kind?, context?, title?,
  domain? }`; `id` is a content-derived SHA-256 prefix.
  `type` is one of `post`, `quote`, `link`, or `video`. `kind` is `"reply"` or
  `"repost"` and appears only together with `context`, which holds
  `{ author, handle, text?, date? }` — the original post being
  answered or reposted. `link` entries flatten `title`/`domain`. Add entries with
  `bin/omarchy-add-entry --type <post|quote|link|video> --text "<...>" --source
  "<url>" [--date <YYYY-MM-DD>]`. For posts, add `--kind reply|repost
  --context-author "<name>" --context-handle "@handle"` (optionally
  `--context-text "<...>" --context-date <YYYY-MM-DD>`); for links add
  `--title "<title>" --domain "<domain>"`.
  See [CONTRIBUTING.md](CONTRIBUTING.md).
- `data/avatar-x.png` is DHH's color photo pre-cropped to circular with alpha,
  used by the panel result rows as a plain `Image` (no mask needed) and by
  the render script as a data URI. `data/avatar.png` is the
  grayscale version, faded into the classic quote-card render.
- Rendered images go to `~/Pictures/dhh/`; the plugin writes only two small
  state files under `~/.local/state/dhh/` — `recent.json` (recent searches) and
  `history.json` (copy history).
- Does not request elevated privileges, runs no background services, and starts
  no second Quickshell process.

## Development checks

```sh
omarchy plugin validate .
node tests/test_search.js
node tests/test_format.js
node tests/test_data.js
node --check search.js SearchWorker.js bin/shared.js bin/omarchy-dhh-render bin/omarchy-add-entry
qmllint -I "$OMARCHY_PATH/shell" Panel.qml Service.qml
```

Note: `qmllint` on `BarWidget.qml` may exit 255 due to a Quickshell tooling
limitation — this is expected, not a regression.

## Remove

```sh
omarchy plugin remove dhh
```

## License

UNLICENSED (all rights reserved); see the `LICENSE` file at the repo root. The
bundled quotes and X posts are public statements by David Heinemeier Hansson,
each linked to its source; the avatar is DHH's public photo. See
[CONTRIBUTING.md](CONTRIBUTING.md) for the contribution rules.
