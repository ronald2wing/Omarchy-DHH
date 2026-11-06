// Entry rules: parsing, the entry shape, identity, the texts a post shows, handles and clipboard text.

// DHH's identity, as his posts and the attribution show it.
export const DHH = Object.freeze({ name: "DHH", fullName: "David Heinemeier Hansson", handle: "@dhh" })

// The displayable fields of an entry, in the order the UI and the history
// file hold them. `id` is the dataset's content-derived id when present.
export const ENTRY_FIELDS = ["id", "text", "type", "source", "date", "context", "kind", "title", "domain"]

// One "@handle " mention, as a RegExp source.
const REPLY_MENTION_SOURCE = "@\\w+\\s+"
// The run of mentions x.com prepends to a reply's text, possibly none, as a
// RegExp source anchored at the start.
export const LEADING_MENTIONS = "^(?:" + REPLY_MENTION_SOURCE + ")*"
// At least one leading mention. Not global, so sharing it never leaves a
// lastIndex behind.
const REPLY_MENTIONS_RE = new RegExp("^(?:" + REPLY_MENTION_SOURCE + ")+")

// The line crediting a post: "— Name (@handle)".
function attribution(name, handle) {
  return "— " + name + " (" + handle + ")"
}
const DHH_ATTRIBUTION = attribution(DHH.fullName, DHH.handle)

// Parse JSON Lines into entry objects, skipping blank and malformed lines.
export function parseJsonl(raw) {
  const out = []
  const lines = String(raw || "").split("\n")
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim()
    if (line === "") continue
    try {
      const e = JSON.parse(line)
      if (e && typeof e === "object") out.push(e)
    } catch (err) { /* skip malformed line */ }
  }
  return out
}

// A new object holding only the ENTRY_FIELDS of `e`, in that order (a field
// `e` lacks is present and undefined). `e` itself is never changed.
export function toEntry(e) {
  const out = {}
  for (let i = 0; i < ENTRY_FIELDS.length; i++) out[ENTRY_FIELDS[i]] = e[ENTRY_FIELDS[i]]
  return out
}

// The referenced post's handle (reply/repost/quote `context`), or "" when
// absent. Coerced so a non-string handle in a hand-edited line cannot throw.
export function contextHandle(e) {
  return e && e.context && e.context.handle ? String(e.context.handle) : ""
}

// Whether the entry is DHH's repost of someone else's post: the card shows
// "DHH reposted" over that post.
export function isRepost(e) {
  return !!e && e.kind === "repost"
}

// Whether the entry shows the post it answers or quotes in a bordered box
// under its body.
export function hasContextCard(e) {
  return !!e && (e.kind === "reply" || e.kind === "quote")
}

// `text`, one of entry `e`'s texts, minus its leading reply mentions when
// `e` references another post, the only entries that carry them.
export function withoutReplyMentions(e, text) {
  const s = String(text || "")
  return contextHandle(e) ? s.replace(REPLY_MENTIONS_RE, "") : s
}

// The entry's own body: its text minus the reply mentions.
export function postBody(e) {
  return withoutReplyMentions(e, e ? e.text : "")
}

// The body a repost shows: the original post's text when the context carries
// it, else the entry's own text (a bare repost), minus the reply mentions.
export function repostedBody(e) {
  return withoutReplyMentions(e, (e && e.context && e.context.text) || (e && e.text))
}

// Content identity: the source URL, falling back to the text. Ids are not
// reliable across sources (history entries stored before ids existed have
// none), so the feed's no-repeat check and history dedup key on content.
export function contentKey(e) {
  return String((e && e.source) || (e && e.text) || "")
}

// Only http(s) sources may be opened in the browser — never file://, magnet:,
// or another scheme that happens to sit in a hand-edited dataset line.
export function isHttpUrl(s) {
  return /^https?:\/\//.test(String(s || ""))
}

// A handle without its leading "@" ("@dhh" -> "dhh").
export function bareHandle(h) {
  return String(h || "").replace(/^@/, "")
}

// Whether a bare handle is one x.com allows: 1-15 letters, digits or
// underscores. Mirrors DHH::Avatars::HANDLE_PATTERN (lib/dhh/avatars.rb),
// which rejects anything else; the panel filters first so it never asks for
// one.
export function isValidHandle(h) {
  return /^[A-Za-z0-9_]{1,15}$/.test(String(h || ""))
}

// The text copied to the clipboard for an entry: body, attribution, source.
// A link entry leads with its title/domain/URL block, then the commentary.
// A bare repost (its context has no text of its own, so `text` holds the
// other person's words) is credited to that author.
export function clipboardText(e) {
  const context = e.context || {}
  const bareRepost = isRepost(e) && !context.text
  const credit = bareRepost && context.author && context.handle
    ? attribution(context.author, context.handle)
    : DHH_ATTRIBUTION
  const url = e.source || ""

  if (e.type === "link") {
    const head = [e.title, e.domain, url].filter(Boolean)
    const parts = [head.join("\n")]
    if (e.text) parts.push("\n" + e.text)
    parts.push("\n" + credit)
    return parts.join("\n")
  }
  const parts = [postBody(e) + "\n\n" + credit]
  if (url) parts.push(url)
  return parts.join("\n")
}
