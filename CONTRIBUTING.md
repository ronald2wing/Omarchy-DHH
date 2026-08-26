# Contributing to the DHH plugin

Contributions arrive as GitHub pull requests.

## Adding an entry

Append one line to `data/quotes.jsonl`. The recommended way is the bundled
helper, which computes the content-derived `id` for you:

```sh
bin/omarchy-add-entry --type post --text "The quote or post text, exactly as published." --source "https://x.com/dhh/status/<status-id>" --date "YYYY-MM-DD" >> data/quotes.jsonl
```

To write the line straight into the dataset — and re-sort the file so it stays
in its canonical order (date ascending, undated last, `id` tiebreak) — pass
`--append [--file data/quotes.jsonl]` instead of redirecting to stdout:

```sh
bin/omarchy-add-entry --type post --text "The quote or post text, exactly as published." --source "https://x.com/dhh/status/<status-id>" --date "YYYY-MM-DD" --append
```

The dataset keeps one canonical order: dated entries first by `date` ascending,
undated entries last, with `id` as the tiebreak. `bin/omarchy-sort-data` applies
exactly this order byte-preservingly, and the `--append` / `--write` helpers
re-sort automatically.

The resulting line has this shape:

```json
{"id": "<8-hex>", "type": "post", "text": "The quote or post text, exactly as published.", "source": "https://x.com/dhh/status/<status-id>", "date": "YYYY-MM-DD"}
```

`id` is the first 8 hex characters of the SHA-256 of `normalize(text)` (trim,
lowercase, collapse whitespace); the helper computes it, so never write it by
hand.

Rules:

- **Public only.** Every entry must link to a source a reviewer can open to
  verify the text. No private or attributed-only quotes.
- **`type`** is one of `"post"` (an X post, source is the status URL), `"quote"`
  (a standalone quote, source is a verifiable public URL, e.g. a
  `signalvnoise.com` essay or `rubyonrails.org/doctrine`), `"link"`, or
  `"video"` (an X video post; `source` is the status URL). `text` ownership
  follows `kind`: for `reply`/`quote` entries `text` is DHH's own words and
  `context.text` (when present) is the other person's; for `repost` entries
  `text` holds the original author's words and `context` carries only
  `author`/`handle`. Imported post text is verbatim and may contain emoji.
- **`kind`** discriminates the quoted-card body, present only together with
  `context` (which carries `{ author, handle, text?, date?, verified?,
  verified_type? }` — the original post being answered, reposted, or quoted).
  `context.verified` is `true` only when the referenced author is actually
  verified; omit it otherwise. `context.verified_type` is `individual`,
  `organization`, or `government` (blue/gold/grey badge) and appears only
  together with `verified: true`; omit it when the variant is unknown. Quotes
  from
  x.com/twitter.com sources, posts, videos, and reply/repost/quote entries
  render as X-post cards; quotes from other sources and links render as the
  classic grayscale card:
  - `kind: "reply"` — `text` is DHH's reply; the original post lives in
    `context`. Renders DHH's body, then the original post as a bordered quoted
    card (with the original author's avatar, name, handle, and time), with no
    separate "Replying to" line.
  - `kind: "quote"` — `text` is DHH's commentary; the quoted post lives in
    `context`. Renders exactly like a reply: DHH's body, then the quoted post
    as a bordered quoted card (with the original author's avatar, name, handle,
    and time).
  - `kind: "repost"` — renders a "DHH reposted" label above the original
    post's body (`context.text` when present, else `text`), with no quoted
    card.
- **`link`** entries flatten `title`/`domain`. Plain `post`/`link`/`video`
  entries carry no `kind`/`context`.
- **`date`** is optional. Omit it when the publication date is unknown; the
  rendered image then omits the timestamp line.
- **Append-only.** Add new lines at the end of the file. Never edit, reorder, or
  delete existing lines — that keeps PR diffs clean.
- **X, never "Twitter".** No "tweet"/"tweeter"/"twitter" in text, docs, or code;
  only `x.com`/`twitter.com` host strings appear. `api.fxtwitter.com` is the one
  accepted third-party host exception (a functional URL, not prose).

## Batch import

`bin/omarchy-fetch-posts` imports DHH's recent posts from `api.fxtwitter.com` as
ready-to-append JSONL lines (oldest first), skipping any post already in the
dataset by `id` or `source`. It emits standalone posts plus reply, repost, and
quote entries with the matching `kind` and `context`. It is a dry run by
default; pass `--write` to append the new lines and re-sort the file.

```sh
bin/omarchy-fetch-posts                 # dry run: print new entries
bin/omarchy-fetch-posts --write         # append and re-sort
bin/omarchy-fetch-posts --pages 3 --write
bin/omarchy-fetch-posts --all --write
```

- `--limit N` — statuses to request per page (1..100, default 100; the API
  returns its own page size regardless).
- `--pages N` — fetch at most `N` cursor pages (default 1), stopping early when
  the cursor runs out or a page adds no new entries.
- `--all` — walk the cursor until it runs out or a page adds no new entries, up
  to a safety cap.

## Before submitting

Run the dataset validation:

```sh
ruby tests/test_data.rb
ruby tests/test_helpers.rb
```

Both must print an `all assertions passed` line. Then open a PR with your
added line(s).
