// Rendered-image rules: which image an entry renders as, and the file it is saved to.

import { hash32 } from "./format.mjs"

// Whether an entry renders as PostImage, x.com's timeline post (posts,
// videos, x.com-sourced quotes and every reply, repost and quote kind),
// rather than QuotationImage (other quotes and links).
export function rendersAsPostImage(e) {
  if (e.type === "link") return false
  if (e.type !== "quote") return true
  return /^https?:\/\/(?:www\.)?(?:x\.com|twitter\.com)(?:\/|$)/.test(String(e.source || ""))
}

// The rendered image's file name: a slug of the text and the entry's id.
// The id is the dataset's (8 hex digits) when it has that shape, else a hash
// of the text, so a malformed line can never steer the path.
export function imageFileName(e) {
  const text = String(e.text || "")
  const slug = text.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 60) || "dhh"
  const id = /^[0-9a-f]{8}$/.test(String(e.id || "")) ? e.id : hash32(text).toString(16).padStart(8, "0")
  return slug + "-" + id + ".png"
}
