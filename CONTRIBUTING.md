# Contributing to the DHH plugin

## Adding an entry

Use `tools/add-entry`. It computes the content-derived `id`, validates the
flags against the schema in `DHH::Dataset`, and with `--write` appends the
line to `data/entries.jsonl` and sorts the file:

```sh
tools/add-entry --type post --text "The post text, exactly as published." \
  --source "https://x.com/dhh/status/<status-id>" --date "YYYY-MM-DD" --write
```

Without `--write` the line is printed to stdout instead (a dry run). The
result has this shape:

```json
{"id":"<8-hex>","type":"post","text":"The post text, exactly as published.","source":"https://x.com/dhh/status/<status-id>","date":"YYYY-MM-DD"}
```

`id` is the first 8 hex characters of the SHA-256 of `normalize(text)` (trim,
lowercase, collapse whitespace). Never write it by hand. `tools/add-entry
--help` lists every flag; `--file PATH` points `--write` at another file.

### Rules

- **Public only.** Every entry links to a source a reviewer can open to verify
  the text. No private or attributed-only quotes.
- **`type`** is `post` (an X post; `source` is the status URL), `quote` (a
  standalone quote; `source` is a public URL such as a `signalvnoise.com`
  essay or `rubyonrails.org/doctrine`), `link` (carries `title` and
  `domain`), or `video` (an X video post).
- **Image routing.** Posts, videos, x.com-sourced quotes and every entry with
  a `kind` render as the x.com post image (`PostImage`); other quotes and
  links render as the quotation image (`QuotationImage`), beside a grayscale
  portrait. `rendersAsPostImage` in `js/rendered-image.mjs` holds the rule.
- **`kind`** marks a post that references another post and always comes with
  `context` = `{ author, handle, text?, date?, verified?, verified_type? }`:
  - `reply`: `text` is DHH's reply; the replied-to post is in `context`.
    Renders DHH's body, then the context as a bordered card (`ContextCard`).
  - `quote`: `text` is DHH's commentary; the quoted post is in `context`.
    Renders like a reply.
  - `repost`: `text` holds the original author's words and `context` carries
    only `author`/`handle`. Renders a "DHH reposted" header above the
    original author's post, with no bordered card.
- **`type: quote` and `kind: quote` share a word** for two different things:
  a standalone quote, and a post quoting another post (see Naming).
- **`context.verified`** is `true` only when the referenced author is actually
  verified; omit it otherwise. **`context.verified_type`** is `individual`,
  `organization` or `government` (blue, gold or grey badge), only alongside
  `verified: true`; omit it when the variant is unknown.
- **`date`** is optional; omit it when the publication date is unknown.
- **Never edit or delete existing lines.**

## Batch import

`tools/import-posts` imports DHH's recent posts from `api.fxtwitter.com` as
dataset lines (oldest first), skipping anything already in the dataset by
`id` or `source` before making any further request for it. It emits
standalone posts plus reply, repost and quote entries with the matching
`kind` and `context`. A dry run prints the new lines; `--write` appends them,
sorts the file and prints the number of new entries. A status that would not
validate is skipped with a warning. The summary goes to stderr either way.

```sh
tools/import-posts [--pages N | --all] [--bare-replies] [--file PATH] [--write]
```

- `--pages N`: walk at most `N` cursor pages (default 1).
- `--all`: walk until the cursor runs out or consecutive empty pages confirm
  the timeline tail, up to a safety cap.
- `--bare-replies`: replies carry only the bare author/handle context, which
  skips one status fetch per reply.
- `--file PATH`: dedupe against and write to `PATH` instead of
  `data/entries.jsonl`.

## Sort order

The file is sorted by `date` ascending, undated entries last, `id` as the
tiebreak. Both tools' `--write` sort the file after appending.

```sh
tools/sort-dataset           # report whether it is sorted
tools/sort-dataset --check   # exit 1 when it is not
tools/sort-dataset --write   # sort it in place
```

Lines are reordered byte for byte; JSON is parsed only to read the keys.

## Schema

The whole schema lives in `DHH::Dataset::SCHEMA` (`lib/dhh/dataset.rb`),
with `ENTRY_TYPES`, `POST_KINDS`, `CONTEXT_KEYS`, `VERIFIED_TYPES` and
`DATE_PATTERN` beside it, and `DHH::Dataset.id_for` derives the id. `tests/ruby/test_dataset.rb`
validates every line against it.

## Architecture

Every fact has one home; a second copy is a bug. The README's Layout table
maps the directories, and each file's header comment says what it holds.

### JS modules in Qt

Measured on Qt 6.12.0 / Quickshell 0.3.2:

- `js/*.mjs` are Qt-free ES modules. QML imports them with
  `import "js/x.mjs" as X` (or `"../js/x.mjs"`), and imports between modules
  resolve transitively. Node runs the same files in the tests.
- The dataset WorkerScript's `source` is `js/dataset-worker.mjs`, and module
  imports work there. Its protocol is index/indexed, search/searched,
  draw/drawn and refresh/refreshed.
- Module-scope `let` survives garbage collection; plain-script top-level
  `let`/`const` crashed under the worker.
- `.import` fails inside a WorkerScript and inside `Qt.include`d files, so
  the plain-script loading forms are not used.
- A module is one instance per QML engine, so module state (the highlight
  query cache) is shared by both monitors' panels; keep it bounded. Each
  WorkerScript gets its own instances.
- Declare a module-scope `const`/`let` above its first textual use. Reading
  one from a function declared above it is safe at run time, but the shell
  logs `qt.qml.usedbeforedeclared`, which neither node nor the headless `qml`
  runner shows.
- Nothing the worker reaches may use `Map`, `Set`, `WeakMap` or `WeakSet`:
  Qt's V4 engine implements their lookups as linear scans. Use
  `Object.create(null)` and typed arrays. `tests/js/test_modules.mjs`
  enforces this by walking the worker's import graph, and also fails on an
  import outside `js/` and on a module nothing uses.
- One home per rule: `js/words.mjs` is the word layer (the tokenizer, the
  stopword table, stored tokenized as `dont`, not `don't`, the plural stem,
  the -ing/-ed forms and `parseQuery`), which `js/search.mjs` and
  `js/highlight.mjs` both use, so the highlighter bolds what search matches.
  Entry rules live in `js/entries.mjs`, rendered-image rules in
  `js/rendered-image.mjs`, and search status copy in `js/search-status.mjs`.

### QML layers and Look

- `model/` holds state and every side effect: `Process`, `FileView`,
  `WorkerScript`, programs started detached and clipboard writes. Every
  program the panel starts detached (`xdg-open`, `wl-copy`) and every
  clipboard write goes through the `model/Desktop` singleton. `model/` holds
  no visual items, and `ui/` only draws. The one exception is
  `ImageRenderer`, which saves its own grab: the grab result exists only in
  the panel's window. `BarWidget.qml` creates the model objects outside the
  lazily built panel body, so state loads before the first open, and binds
  `active` to the open state on those that work only while open (`Dataset`,
  `PostCount`, `AvatarCache`). `tests/ruby/test_contracts.rb` enforces the
  split.
- `Look` and `Desktop` are `pragma Singleton`s declared in `ui/base/qmldir`
  and `model/qmldir`. Once a directory has a `qmldir`, only the types it
  lists resolve there, so every `.qml` in `ui/base` and `model` must be
  listed. qmllint needs each qmldir passed with `-i`, or it reports the
  singleton as undeclared; `tests/run` does that. Every `.qml` starts with
  `pragma ComponentBehavior: Bound`, after `pragma Singleton` in a singleton.
- Every monitor's `BarWidget` assigns `Look.barForeground`, and today they
  all write the same value (the bar's foreground, else `Color.foreground`).
  If bar foregrounds ever differ per monitor, the hover and selection fills
  must go back to being computed per instance.
- Every `Look` property and function is read somewhere: as `Look.<name>`
  outside `Look.qml`, or by another `Look` binding (a measured part of a
  composed value, such as `repostLabelLead`). `test_contracts.rb` fails on
  an unused token.
- Icons live in `assets/icons/<name>.svg`, with `<name>-hover.svg` variants
  that differ only by fill; `Look.icon(name, hoverVariant)` resolves them. A
  variant that is not a hover state is named by its colour (`grok-light`,
  `xmark-dark`, `verified-blue`). Each file in `assets/images` is named in
  kebab-case after its `Look` token (`dhh-avatar.png` is `Look.dhhAvatar`).

### x.com fidelity

- x.com's geometry, palette and type scale live in `Look`, in CSS pixels,
  and are never scaled with the shell's spacing (only panel chrome uses
  `Style`). Every x.com value is measured from x.com's computed styles,
  element boxes and screenshot pixels in DevTools, never recalled;
  `Look.qml`'s comments record what each one measures. Change one only with
  a new measurement.
- x.com's Chirp is not ours to ship; Adwaita Sans (Inter, a dependency of
  GTK and Plymouth) draws the text. Where a post body breaks, and how wide
  each line is, come from Chirp itself: `js/chirp-metrics.mjs` holds its
  advances and kerning as measured on x.com, and `js/line-layout.mjs` breaks
  the body as x.com does (`pre-wrap`, `break-word`, hanging spaces, breaks
  after a hyphen between word characters, around dashes and between
  ideographs, never after `/`) and gives each line Chirp's width.
  `ui/post/PostBody.qml` draws those lines, opening or closing each line's
  letters so it ends where x.com's does, sizes its box to exactly the lines
  times `Look.bodyLineHeight` with the glyphs centred as CSS does, and draws
  emoji at x.com's size. A character Chirp was not measured for takes
  Adwaita Sans's width.
- To re-measure, run `dev/measure-chirp.js` in DevTools on an x.com post
  with an emoji, then
  `node dev/generate-chirp-metrics.mjs ~/Downloads/xcom-metrics.json`, which
  rewrites `js/chirp-metrics.mjs` and `tests/js/chirp-check-lines.json`.
- Text other than post bodies (names, handles) uses Adwaita Sans with letter
  spacing fitted to Chirp (`Look.letterSpacingFor(weight)`). Text primitives
  (`XText`) take `weight` rather than `font.bold`, so the spacing follows the
  weight: binding `font.letterSpacing` to `font.bold` in the same font group
  loops.

### One TimelinePost for both surfaces

- `ui/post/TimelinePost.qml` is the one drawing of x.com's timeline post:
  repost header, author line, body, context card and action row. The
  panel's `PostCard` (selection, the copy surface, the divider, the Copied
  confirmation) and the saved `PostImage` (a black 598px column) are thin
  wrappers around it, so a post is the same in the panel and in the image.
- `bodyHtml` is the entry's own body (`Entries.postBody`), escaped, with
  search highlights in the panel; for a repost, `TimelinePost` alone
  substitutes the reposted post's body (`Entries.repostedBody`).
- `interactive: false` draws the image: no hover, no clicks. It also
  switches the one part that differs, the head's Grok and "..." marks:
  hover discs in the panel, plain icons in the image, where the Grok mark
  sits a fraction of a pixel apart (measured; see the comment in
  `TimelinePost.qml`).
- `curveRendered: true` (the image) curve-renders every text, through
  `XText.curveRendered` and `PostBody.curveRendered`, so the text stays
  exact when the image is grabbed at twice its size. The panel never sets a
  render type: a `Binding` with `when` leaves Qt's default in place.
- `textColor` and `avatarPixelRatio` carry the rest of the difference: the
  theme's text colour and the screen's pixel ratio in the panel,
  `Look.surfaceText` and `Look.imageScale` in the image.

### Rendered images

- `rendersAsPostImage` in `js/rendered-image.mjs` picks the image (see
  Image routing above), and `imageFileName` names its file.
- `ui/render/ImageRenderer.qml` keeps both images built off to the side of
  the panel (a grab needs an item in a shown window, so renders start from
  the open panel). A render first asks `AvatarCache` for a missing context
  avatar and waits until its fetch finishes (`awaitsFetch`; a failed fetch
  finishes too). It then shows the entry and grabs on the first frame
  where the image folder exists (`ImageFolder` runs `mkdir -p` on the first
  render), two frames have passed so the image's size is final, and no
  `Image` item in it is still loading.
- The grab is `Look.imageScale` (2x) divided by the window's scale. The PNG
  is saved into the folder, put on the clipboard with
  `Desktop.copyImageFile`, and shown in `RenderPreview`. A render that has
  not finished after 8 s fails, so nothing can wedge the renderer.
- `QuotationImage` is image-only, so it sets its render type outright.

### Tests

`tests/run` runs every check and stops at the first failure:
`omarchy plugin validate .`, `ruby -c` and `node --check` over every script
(`dev/` included), qmllint over the QML (from `/usr/lib/qt6/bin`, with an
import root holding a `qs` link to the shell), the hardened-shebang check,
then every Ruby and JS test.

- Run one test file on its own with `ruby tests/ruby/test_<name>.rb` or
  `node tests/js/test_<name>.mjs`. Each file's first line says what it
  covers. For a dataset-only change, `ruby tests/ruby/test_dataset.rb` is
  the relevant one.
- `tests/ruby/test_contracts.rb` holds the rules that span files: no
  clipboard-reading text control, icon and asset names that resolve and are
  used, `helpers/` that are named and executable, qmldirs that list their
  directory, the `pragma` header, the layer rules, no literal invisible
  characters, the manifest, and every `Look` token used.
- `tests/js/test_format.mjs` and `test_entries.mjs` hold input/expected
  tables for `js/format.mjs` and the body functions of `js/entries.mjs`,
  run by the shared `tests/js/cases.mjs`: a listed export must exist and
  have cases, and every `format.mjs` export must be listed.
- `tests/ruby/test_helper.rb` holds what the Ruby tests share: assertions,
  output capture, loopback HTTP servers and image fixtures. No test reaches
  the network.

## Naming

- **entry** in code and data, **post** in UI copy, **x.com** in prose.
- The other post an entry references is its **context**, drawn as the
  bordered `ContextCard` when `Entries.hasContextCard(entry)`. A repost has a
  context but no card: `Entries.isRepost(entry)` draws the "DHH reposted"
  header instead.
- **Kept deliberately:** x.com calls a post that quotes another post a
  quote, and the standalone `type: quote` predates it; so `type: quote` (a
  standalone quote) and `kind: quote` (a post quoting another post) share
  the word. No dataset or state migration.
- The reply/repost/like/views icons and counts are **engagement**
  (`EngagementCount`); **metrics** means only font metrics (Chirp's
  advances and kerning).
- `TimelinePost` is the drawing, `PostCard` the panel row around it, and
  `PostImage`/`QuotationImage` the two saved images. `PostBody` draws the
  text `Entries.postBody` returns.
- A record's indexed form in the worker is a **doc**; a ListModel element is
  a **row** `{ entry, bodyHtml }`; the user's text is the **query**; the
  worker's answer is a **response** ("reply" means only the post kind); a
  random sample is a **draw**, and `drawTag` says whose it is. Random posts
  under "No results" are the **filler**.
- In a query, a word that must match is a **filter**; a **term** is an
  indexed word.
- Two entries are the same when their **contentKey** (source URL, else text)
  matches.
- A context author's avatar is **settled** once its fetch has finished, with
  or without an image.
- A `helpers/` program is a **helper**, a `tools/` program a **tool**.
- The dataset is **sorted** (`DHH::Dataset.sort_lines`, `sorted?`, `sort!`).
- `max<Thing>` for every cap; **deadline** for a whole operation, **timeout**
  for one hop.
- `<verb>Requested` for signals going up the UI (`leaveRequested`) and
  `<noun>Confirmed` for a confirmation (`queryConfirmed`); past participles
  for worker responses and model signals (`searched`, `drawn`, `succeeded`,
  `failed`).
- **shown** means visible, **active** means doing work, and **opened** is
  only the panel's state. A panel view's non-visual state is `<View>State`
  (`FeedState`, `ResultsState`); a **page** is one `pageSize` batch of
  posts.
- A property is named after its type (`imageFolder: ImageFolder`,
  `dataset: Dataset`). A member only its own file uses lives in `internal`,
  and model state one owner sets is `readonly` to everyone else.
- `remember` / `forget` / `clear` / `replaceAll` for a `PersistedList`; its
  file is read on load and written only by a change.
- **X, never "Twitter".** No "tweet" or "twitter" in identifiers, comments,
  UI strings or docs; only the `x.com`/`twitter.com` host strings and the
  fxtwitter API's own field names appear. `api.fxtwitter.com` is the one
  accepted third-party host. Quoted post text is exempt.

## Security invariants

- Every `helpers/` and `tools/` file starts with the hardened shebang, which
  strips `RUBYOPT`, `RUBYLIB` and the gem/bundler variables; `tests/run`
  checks the exact line.
- `lib/dhh.rb` scrubs those variables again at require time, and every
  `BUNDLE_*` key, not just the three the shebang names, so no program has to
  remember to.
- Byte caps: `HelperProcess.maxStdoutBytes` on helper output, and the
  `DHH::HTTP` body caps on every fetch (with the per-avatar and per-batch
  caps on top).
- Time bounds: every helper runs under a `HelperProcess` deadline and kill
  grace; every HTTP hop has a timeout, and an avatar batch shares one
  `DHH::Deadline`. A render gives up after 8 s.
- Names, handles and captions are `Text.PlainText`. Post bodies and
  suggestion labels are `Text.RichText` built only from `escapeHtml`'d
  segments (and emoji matched code point by code point) plus fixed `<b>`,
  `<span>`, `<div>` and `<br>` tags. An image's file name is a slug of its
  text plus the dataset id (8 hex digits) or a hash, so no entry field can
  steer the path.
- `Desktop.openUrl` opens only `http(s)` URLs, so an entry's source never
  reaches `xdg-open` as a file, a scheme handler or an option.
  `Desktop.copyImageFile` passes the path to `sh` as an argument, never as
  code.
- `Entries.isValidHandle` filters handles in QML before they reach
  `helpers/fetch-avatars`, which applies `DHH::Avatars::HANDLE_PATTERN` again.
- No clipboard-reading text controls: Qt 6.12's `TextInput`/`TextField` read
  the whole clipboard on every clipboard change, so the search field is the
  one `TextArea`, and `tests/ruby/test_contracts.rb` rejects the others.

## Before submitting

```sh
tests/run
```

For a change to the QML, also check it in the running shell. The plugin
installed at `~/.config/omarchy/plugins/dhh` is a clone of this repository:
commit, then `git -C ~/.config/omarchy/plugins/dhh fetch` and
`git -C ~/.config/omarchy/plugins/dhh checkout -B main origin/main`, run
`omarchy-restart-shell`, wait about 30 s for the plugins to load, then
`omarchy-shell dhh open`. Check both monitors when the change touches
`BarWidget.qml` or `model/`, and read the shell log for `ReferenceError`,
`TypeError`, `is not defined` and `Cannot assign`.

Contributions arrive as GitHub pull requests.
