"use strict"
const fs = require("fs")
const path = require("path")
const shared = require("../bin/shared")

const Search = shared.loadScript(path.join(__dirname, "..", "search.js"))

const file = path.join(__dirname, "..", "data", "quotes.jsonl")
const raw = fs.readFileSync(file, "utf8")
const lines = raw.split("\n").filter((l) => l.trim() !== "")

function assert(cond, msg) {
  if (!cond) throw new Error("FAIL: " + msg)
}

// Per-type schema: every entry must carry the `required` keys and may carry the
// `optional` keys. `type` selects the registry entry. `post` entries that
// reference another post carry a `context` object plus a `kind` tag
// (`"reply"` or `"repost"`); `link` keeps flat `title`/`domain` fields.
const SCHEMA = {
  post: { required: ["id", "text", "type", "source"], optional: ["date", "kind", "context"] },
  quote: { required: ["id", "text", "type", "source"], optional: ["date"] },
  link: { required: ["id", "text", "type", "source", "title", "domain"], optional: ["date"] },
  video: { required: ["id", "text", "type", "source"], optional: ["date"] }
}

assert(lines.length >= 10, "dataset has at least 10 entries")

const seen = new Set()
for (const line of lines) {
  const o = JSON.parse(line)

  assert(typeof o.type === "string" && SCHEMA[o.type] !== undefined, "type is a known schema key: " + line)

  const schema = SCHEMA[o.type]
  for (const key of schema.required) {
    assert(o[key] !== undefined, "required key present: " + key + " in " + line)
  }
  for (const key of Object.keys(o)) {
    assert(schema.required.indexOf(key) !== -1 || schema.optional.indexOf(key) !== -1, "unknown key: " + key + " in " + line)
  }

  if (o.context !== undefined) {
    const ctx = o.context
    assert(ctx !== null && typeof ctx === "object" && !Array.isArray(ctx), "context is a plain object: " + line)
    assert(typeof ctx.author === "string" && ctx.author.trim() !== "", "context.author is non-empty string: " + line)
    assert(typeof ctx.handle === "string" && ctx.handle.trim() !== "", "context.handle is non-empty string: " + line)
    if (ctx.text !== undefined) assert(typeof ctx.text === "string" && ctx.text.trim() !== "", "context.text is non-empty string: " + line)
    if (ctx.date !== undefined) assert(typeof ctx.date === "string" && /^\d{4}-\d{2}-\d{2}$/.test(ctx.date), "context.date format YYYY-MM-DD: " + line)
    assert(typeof o.kind === "string" && (o.kind === "reply" || o.kind === "repost"), "kind present and valid when context present: " + line)
  } else {
    assert(o.kind === undefined, "kind present only with context: " + line)
  }

  assert(typeof o.text === "string" && o.text.trim() !== "", "text is non-empty string: " + line)
  assert(typeof o.id === "string" && o.id === Search.entryId(o.text, shared.sha256Hex), "id matches sha256(normalize(text)): " + line)
  assert(typeof o.source === "string" && o.source.trim() !== "", "source is non-empty string: " + line)
  assert(o.source.startsWith("https://"), "source is https URL: " + line)
  if (o.date !== undefined) {
    assert(typeof o.date === "string" && /^\d{4}-\d{2}-\d{2}$/.test(o.date), "date format YYYY-MM-DD: " + line)
  }
  assert(!seen.has(o.source), "duplicate source: " + o.source)
  seen.add(o.source)
}

console.log("test_data.js: all assertions passed (" + lines.length + " entries)")
