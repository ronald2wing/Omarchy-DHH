# Contributing to the DHH plugin

Thanks for adding to the DHH quotes and X posts collection. Contributions arrive
as GitHub pull requests.

## Adding an entry

Append one line to `data/quotes.jsonl`. The recommended way is the bundled
helper, which computes the content-derived `id` for you:

```sh
bin/omarchy-add-entry --type post --text "The quote or post text, exactly as published." --source "https://x.com/dhh/status/<status-id>" --date "YYYY-MM-DD" >> data/quotes.jsonl
```

The resulting line has this shape:

```json
{"id": "<8-hex>", "type": "post", "text": "The quote or post text, exactly as published.", "source": "https://x.com/dhh/status/<status-id>", "date": "YYYY-MM-DD"}
```

`id` is the first 8 hex characters of the SHA-256 of `normalize(text)` (trim,
lowercase, collapse whitespace); the helper computes it, so never write it by
hand.

Rules:

- **Public only.** You may only add quotes/posts that are public and that you
  can link to a source a reviewer can open to verify the text. No private or
  attributed-only quotes.
- **`type`** is one of `"post"` (an X post, source is the status URL), `"quote"`
  (a standalone quote, source is a verifiable public URL, e.g. a
  `signalvnoise.com` essay or `rubyonrails.org/doctrine`), `"link"`, or
  `"video"`. `text` is DHH's own words in every entry, EXCEPT the single bare
  repost (id `1d7ae346`, Chad Fowler): there `text` holds the other person's
  words and `context.text` is omitted, so the renderer falls back to `text` for
  the quoted card.
- **`kind`** discriminates the quoted-card body, present only together with
  `context` (which carries `{ author, handle, text?, date? }` — the
  original post being answered or reposted). The top-level card style is chosen
  by `isQuote` (type + source): quotes from x.com/twitter.com sources, posts,
  videos, and reply/repost entries render as X-post cards; quotes from other
  sources and links render as the classic grayscale card:
  - `kind: "reply"` — `text` is DHH's reply; the original post lives in
    `context`. Renders DHH's body, then the original post as a bordered quoted
    card (with the original author's avatar, name, handle, and time), with no
    separate "Replying to" line.
  - `kind: "repost"` — renders DHH's body plus the quoted card, with no
    replying-to line. The quoted card shows `context.text` when present.
- **`link`** entries flatten `title`/`domain`. Plain `post`/`link`/`video`
  entries carry no `kind`/`context`.
- **`date`** is optional. Omit it when the publication date is unknown; the
  rendered image then omits the timestamp line.
- **Append-only.** Add new lines at the end of the file. Never edit, reorder, or
  delete existing lines — that keeps PR diffs clean.
- **No Twitter terminology.** The platform is X. Never use "tweet"/"tweeter"/
  "tweeted" in the entry text or anywhere else.

## Before submitting

Run the dataset validation:

```sh
node tests/test_data.js
```

It must print `test_data.js: all assertions passed`. Then open a PR with your
added line(s) and a note on where each source can be verified.
