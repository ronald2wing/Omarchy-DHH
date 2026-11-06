// js/rendered-image.mjs: which image an entry renders as, and its file name.
import assert from "node:assert/strict"
import * as R from "../../js/rendered-image.mjs"

// rendersAsPostImage: posts, videos and x.com-sourced quotes render as
// PostImage; other quotes and links as QuotationImage.
assert(R.rendersAsPostImage({ type: "post", text: "a" }), "rendersAsPostImage: a post")
assert(R.rendersAsPostImage({ type: "video", text: "a" }), "rendersAsPostImage: a video")
assert(R.rendersAsPostImage({ type: "quote", text: "a", source: "https://x.com/dhh/status/1" }), "rendersAsPostImage: an x.com quote")
assert(R.rendersAsPostImage({ type: "quote", text: "a", source: "https://www.twitter.com/dhh" }), "rendersAsPostImage: a twitter.com quote")
assert(!R.rendersAsPostImage({ type: "quote", text: "a", source: "https://x.company.com/" }), "rendersAsPostImage: a look-alike host is a quotation")
assert(!R.rendersAsPostImage({ type: "quote", text: "a", source: "https://signalvnoise.com/" }), "rendersAsPostImage: another quote")
assert(!R.rendersAsPostImage({ type: "link", text: "a", source: "https://x.com/dhh" }), "rendersAsPostImage: a link is always a quotation")

// imageFileName: a 60-character slug and the dataset id, or a hash of the
// text when the id is missing or malformed.
assert.equal(R.imageFileName({ id: "c4639082", text: "Rails Doctrine! 2024" }), "rails-doctrine-2024-c4639082.png", "imageFileName: slug and id")
assert.equal(R.imageFileName({ id: "c4639082", text: "  --  " }), "dhh-c4639082.png", "imageFileName: an empty slug falls back to dhh")
assert.equal(R.imageFileName({ id: "c4639082", text: "x".repeat(100) }), "x".repeat(60) + "-c4639082.png", "imageFileName: the slug stops at 60")
assert(/^meetings-are-toxic-[0-9a-f]{8}\.png$/.test(R.imageFileName({ text: "Meetings are toxic!" })), "imageFileName: no id hashes the text")
assert(/^a-[0-9a-f]{8}\.png$/.test(R.imageFileName({ id: "../../etc", text: "a" })), "imageFileName: a malformed id never reaches the path")
assert.equal(R.imageFileName({ text: "a" }), R.imageFileName({ id: "../../etc", text: "a" }), "imageFileName: a malformed id is ignored")

console.log("test_rendered_image.mjs: all assertions passed")
