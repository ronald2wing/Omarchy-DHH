// js/entries.mjs: the body functions through their case table, then the entry shape, identity, handles and clipboard text.
import assert from "node:assert/strict"
import * as E from "../../js/entries.mjs"
import { assertCases } from "./cases.mjs"

// An entry that references another post, so its texts lose their leading
// reply mentions.
const REPLY = { kind: "reply", text: "@foo hi", context: { handle: "@foo" } }

assertCases(E, {
  withoutReplyMentions: [
    { args: [REPLY, "@foo hi"], expected: "hi" },
    { args: [REPLY, "@foo @bar hi"], expected: "hi" },
    { args: [REPLY, "@foo\n\n@bar_2 hi"], expected: "hi" },
    { args: [REPLY, "@foo\u00a0hi"], expected: "hi" },
    { args: [REPLY, "@foo\t\n\u000b\f\r \u00a0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u2028\u2029\u202f\u205f\u3000\ufeffhi"], expected: "hi" },
    { args: [REPLY, "@foo\u200bhi"], expected: "@foo\u200bhi" },
    { args: [REPLY, "@foo\u0085hi"], expected: "@foo\u0085hi" },
    { args: [REPLY, "@foo\u000bhi"], expected: "hi" },
    { args: [REPLY, "@foo"], expected: "@foo" },
    { args: [REPLY, "no mention"], expected: "no mention" },
    { args: [REPLY, "One more thing.\n\n@dhh is coming"], expected: "One more thing.\n\n@dhh is coming" },
    { args: [REPLY, "@café hi"], expected: "@café hi" },
    { args: [REPLY, ""], expected: "" },
    { args: [REPLY, null], expected: "" },
    { args: [REPLY, 123], expected: "123" },
    { args: [{ text: "@foo hi" }, "@foo hi"], expected: "@foo hi" },
    { args: [{ context: { handle: "" } }, "@foo hi"], expected: "@foo hi" },
    { args: [null, "@foo hi"], expected: "@foo hi" },
    { args: [null, 123], expected: "123" }
  ],
  postBody: [
    { args: [{ text: "@a @b reply", context: { handle: "@a" } }], expected: "reply" },
    { args: [{ text: "@a plain" }], expected: "@a plain" },
    { args: [{ text: "@a plain", context: { author: "A" } }], expected: "@a plain" },
    { args: [{ text: "@a plain", context: { handle: "" } }], expected: "@a plain" },
    { args: [{ text: "@a plain", context: "not an object" }], expected: "@a plain" },
    { args: [{ text: "Line one.\n@a line two", context: { handle: "@a" } }], expected: "Line one.\n@a line two" },
    { args: [{ context: { handle: "@a" } }], expected: "" },
    { args: [null], expected: "" }
  ],
  repostedBody: [
    { args: [{ kind: "repost", text: "@x Their words", context: { author: "A", handle: "@a" } }], expected: "Their words" },
    { args: [{ kind: "repost", text: "DHH's comment", context: { handle: "@a", text: "@b @c Original post" } }], expected: "Original post" },
    { args: [{ kind: "repost", text: "Own text", context: { handle: "@a", text: "" } }], expected: "Own text" },
    { args: [{ kind: "repost", text: "@a t", context: { text: "@b original" } }], expected: "@b original" },
    { args: [{ kind: "repost", context: { handle: "@a" } }], expected: "" },
    { args: [null], expected: "" }
  ]
}, "entries.mjs")

// parseJsonl: blank and malformed lines are skipped, objects survive.
const parsed = E.parseJsonl('{"text":"a"}\n\nnot json\n{"text":"b"}\n42\n')
assert.deepEqual(parsed.map(e => e.text), ["a", "b"], "parseJsonl keeps objects, skips blank/malformed/scalar lines")
assert.deepEqual(E.parseJsonl(""), [], "parseJsonl empty input")
assert.deepEqual(E.parseJsonl(null), [], "parseJsonl null input")

// toEntry: only the displayable fields, in ENTRY_FIELDS order, as a copy.
const raw = { id: "1", text: "t", type: "post", source: "s", date: "d", extra: 1 }
const picked = E.toEntry(raw)
assert.deepEqual(Object.keys(picked), E.ENTRY_FIELDS, "toEntry key set")
assert.deepEqual(E.ENTRY_FIELDS, ["id", "text", "type", "source", "date", "context", "kind", "title", "domain"], "ENTRY_FIELDS order")
assert(!("extra" in picked), "toEntry drops unknown fields")
assert(picked !== raw && raw.extra === 1 && raw.text === "t", "toEntry leaves its argument alone")

// contextHandle: string handle passes through, missing handle -> "".
assert(E.contextHandle({ context: { handle: "@janedoe" } }) === "@janedoe", "contextHandle string handle")
assert(E.contextHandle({ context: { handle: "" } }) === "", "contextHandle empty handle")
assert(E.contextHandle({ context: {} }) === "", "contextHandle missing handle")
assert(E.contextHandle({}) === "", "contextHandle missing context")
assert(E.contextHandle(null) === "", "contextHandle null entry")
assert(E.contextHandle({ context: { handle: 42 } }) === "42", "contextHandle numeric handle coerced")

// isRepost and hasContextCard: by kind.
assert(E.isRepost({ kind: "repost" }) && !E.isRepost({ kind: "reply" }) && !E.isRepost({}) && !E.isRepost(null), "isRepost")
assert(E.hasContextCard({ kind: "reply" }) && E.hasContextCard({ kind: "quote" }), "hasContextCard: reply and quote")
assert(!E.hasContextCard({ kind: "repost" }) && !E.hasContextCard({ type: "quote" }) && !E.hasContextCard(null), "hasContextCard: nothing else")

// withoutReplyMentions gives the same answer twice: its RegExp is not
// global, so it keeps no lastIndex between calls.
assert(E.withoutReplyMentions(REPLY, "@a hi") === "hi" && E.withoutReplyMentions(REPLY, "@a hi") === "hi", "withoutReplyMentions twice")

// LEADING_MENTIONS: a RegExp source for any run of leading mentions, none
// included.
assert.equal(new RegExp(E.LEADING_MENTIONS).exec("@a @b hi")[0], "@a @b ", "LEADING_MENTIONS: the run")
assert.equal(new RegExp(E.LEADING_MENTIONS).exec("hi @a")[0], "", "LEADING_MENTIONS: none")

// DHH's identity, frozen.
assert.deepEqual(E.DHH, { name: "DHH", fullName: "David Heinemeier Hansson", handle: "@dhh" }, "DHH")
assert(Object.isFrozen(E.DHH), "DHH is frozen")

// contentKey: source first, text as the fallback.
assert(E.contentKey({ source: "s", text: "t" }) === "s", "contentKey prefers source")
assert(E.contentKey({ text: "t" }) === "t", "contentKey falls back to text")
assert(E.contentKey(null) === "", "contentKey null entry")

// isHttpUrl: only http(s) may be opened.
assert(E.isHttpUrl("https://x.com/dhh") && E.isHttpUrl("http://a.b"), "isHttpUrl accepts http(s)")
assert(!E.isHttpUrl("file:///etc/passwd") && !E.isHttpUrl("magnet:?x") && !E.isHttpUrl(""), "isHttpUrl rejects other schemes")

// bareHandle / isValidHandle: the panel's pre-filter before helpers/fetch-avatars.
assert(E.bareHandle("@dhh") === "dhh" && E.bareHandle("dhh") === "dhh" && E.bareHandle(null) === "", "bareHandle strips one @")
assert(E.bareHandle("@@x") === "@x", "bareHandle strips only one @")
assert(E.isValidHandle("dhh") && E.isValidHandle("jason_fried1") && E.isValidHandle("a".repeat(15)), "isValidHandle accepts x.com handles")
assert(!E.isValidHandle("@dhh") && !E.isValidHandle("") && !E.isValidHandle("a".repeat(16)), "isValidHandle rejects @, empty and over 15")
assert(!E.isValidHandle("a-b") && !E.isValidHandle("café") && !E.isValidHandle("a b") && !E.isValidHandle(null), "isValidHandle rejects other characters")

// clipboardText: body, blank line, attribution, source URL.
const DHH = "— David Heinemeier Hansson (@dhh)"
assert(E.clipboardText({ type: "post", text: "Meetings are toxic.", source: "https://x.com/dhh/status/1" })
  === "Meetings are toxic.\n\n" + DHH + "\nhttps://x.com/dhh/status/1", "clipboardText post")
assert(E.clipboardText({ type: "quote", text: "Q" }) === "Q\n\n" + DHH, "clipboardText without a source omits the URL line")
assert(E.clipboardText({ type: "post", text: "@a @b reply", kind: "reply", source: "u", context: { handle: "@a" } })
  === "reply\n\n" + DHH + "\nu", "clipboardText strips reply mentions")
// A bare repost is credited to the original author.
assert(E.clipboardText({ type: "post", text: "Their words", kind: "repost", source: "u",
                         context: { author: "Jane Doe", handle: "@janedoe" } })
  === "Their words\n\n— Jane Doe (@janedoe)\nu", "clipboardText bare repost attribution")
// A repost whose context holds the original text copies DHH's own words,
// credited to DHH.
assert(E.clipboardText({ type: "post", text: "My comment", kind: "repost", source: "u",
                         context: { author: "Jane Doe", handle: "@janedoe", text: "Their words" } })
  === "My comment\n\n" + DHH + "\nu", "clipboardText repost with context text")
// A link leads with title/domain/URL, then the commentary, then DHH.
assert(E.clipboardText({ type: "link", title: "T", domain: "d.com", source: "https://d.com/p", text: "Commentary" })
  === "T\nd.com\nhttps://d.com/p\n\nCommentary\n\n" + DHH, "clipboardText link")
assert(E.clipboardText({ type: "link", source: "https://d.com/p", text: "C" })
  === "https://d.com/p\n\nC\n\n" + DHH, "clipboardText link without title/domain")

console.log("test_entries.mjs: all assertions passed")
