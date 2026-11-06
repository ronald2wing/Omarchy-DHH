// js/highlight.mjs: highlighting, completions and the bounded query cache.
import assert from "node:assert/strict"
import * as H from "../../js/highlight.mjs"

// highlightHtml: match raw text, escape each segment.
assert(H.highlightHtml("hello <world>", "") === "hello &lt;world&gt;", "highlightHtml empty query escapes")
assert(H.highlightHtml("hello world", "world") === "hello <b>world</b>", "highlightHtml word")
assert(H.highlightHtml("a & b", "&") === "a <b>&amp;</b> b", "highlightHtml query &")
assert(H.highlightHtml("1 < 2", "<") === "1 <b>&lt;</b> 2", "highlightHtml query <")
assert(H.highlightHtml("cost & profit", "amp") === "cost &amp; profit", "highlightHtml never matches inside an entity")
assert(H.highlightHtml("meetings are toxic", "toxic meetings") === "<b>meetings</b> are <b>toxic</b>", "highlightHtml multi-word")
assert(H.highlightHtml("Hello World", "hello") === "<b>Hello</b> World", "highlightHtml case-insensitive")
assert(H.highlightHtml("a.b", ".") === "a<b>.</b>b", "highlightHtml escapes regex metacharacters")

// highlightHtml mirrors search: whole words, never substrings or URLs.
const h = H.highlightHtml
assert(h("Constraints liberate even the most able minds.", "ruby on rails") === "Constraints liberate even the most able minds.", "highlightHtml never bolds inside a word")
assert(h("Ruby on Rails is on fire", "ruby on rails") === "<b>Ruby on Rails</b> is on fire", "highlightHtml bolds the phrase; a lone stopword stays plain")
assert(h("Ruby on Rails is great", "ruby on ra") === "<b>Ruby on Ra</b>ils is great", "highlightHtml open phrase")
assert(h("Rails and Ubuntu", "ra") === "<b>Ra</b>ils and Ubuntu", "highlightHtml typed prefix of the open word")
assert(h("Rails and Ubuntu", "ra ") === "Rails and Ubuntu", "highlightHtml closed word is exact")
assert(h("they said hey", "hey") === "they said <b>hey</b>", "highlightHtml hey is not they")
assert(h("Toxic meetings, one meeting", "meeting ") === "Toxic <b>meetings</b>, one <b>meeting</b>", "highlightHtml plural variants")
assert(h("Thanks @jasonfried and Jason", "jason fried") === "Thanks @<b>jasonfried</b> and <b>Jason</b>", "highlightHtml joined words")
assert(h("see https://rubyonrails.org/rails now rails", "rails") === "see https://rubyonrails.org/rails now <b>rails</b>", "highlightHtml skips URLs")
assert(h("Only on X, go on", "on") === "Only <b>on</b> X, go <b>on</b>", "highlightHtml stopword-only query")
assert(h("DHH’s take on dhh's", "dhh") === "<b>DHH’s</b> take on <b>dhh&#39;s</b>", "highlightHtml possessives")
assert(h("an ai airpod", "ai") === "an <b>ai</b> <b>ai</b>rpod", "highlightHtml exact word and prefix")
// Phrases across apostrophes and possessives, joined pairs, URLs, accented
// words and prefixes around an apostrophe.
assert(h("Well I don’t know", "i don't know ") === "Well <b>I don’t know</b>", "highlightHtml phrase across a curly contraction")
assert(h("Read dhh's book", "dhh book ") === "Read <b>dhh&#39;s book</b>", "highlightHtml phrase across a possessive")
assert(h("I mean anyway, fine", "any way ") === "I mean <b>anyway</b>, fine", "highlightHtml joined pair starting with a stopword")
assert(h("see https://x.com/ruby-on-rails now", "ruby on rails ") === "see https://x.com/ruby-on-rails now", "highlightHtml never bolds a phrase inside a URL")
assert(h("café latte", "f latte ") === "café <b>latte</b>", "highlightHtml phrase never starts inside an accented word")
assert(h("I don't care", "don") === "I <b>don</b>&#39;t care", "highlightHtml prefix before an apostrophe")
assert(h("I don't care", "dont") === "I <b>don&#39;t</b> care", "highlightHtml prefix spanning an apostrophe")
assert(h("The news today, new things", "news ") === "The <b>news</b> today, new things", "highlightHtml news is not new")
// -ing/-ed forms and the corrected query the panel passes back in.
assert(h("Hotwiring Rails; Hotwire", "hotwire ") === "<b>Hotwiring</b> Rails; <b>Hotwire</b>", "highlightHtml -ing form of the word")
assert(h("We shipped the ship", "shipping ") === "We <b>shipped</b> the <b>ship</b>", "highlightHtml base and -ed form of an -ing word")
assert(h("Omarchy for everyone", "omarchy ") === "<b>Omarchy</b> for everyone", "highlightHtml corrected query closed with a space")
assert(h("Even so, good evening", "evening ") === "Even so, good <b>evening</b>", "highlightHtml evening is not even")
assert(h("Ships are shipping", "ships ") === "<b>Ships</b> are <b>shipping</b>", "highlightHtml plural reaches the -ing form")
assert(h("I don't care.", "dont care ") === "I <b>don&#39;t care</b>.", "highlightHtml phrase across an apostrophe the query lacks")

// The query cache is shared by both monitors' panels; it stays bounded, also
// for word-less queries (the substring form shares the cache).
for (let i = 0; i < 100; i++) H.highlightHtml("probe", "q" + i)
assert(H.cachedQueryCount() > 0 && H.cachedQueryCount() <= 64, "highlightHtml query cache bounded")
for (let i = 0; i < 100; i++) H.highlightHtml("a.b", ".".repeat(i + 1))
assert(H.cachedQueryCount() <= 64, "highlightHtml query cache bounded for substring queries")
// A cached query gives the same answer the second time.
assert(H.highlightHtml("Rails and Ubuntu", "ra") === "<b>Ra</b>ils and Ubuntu" && H.highlightHtml("Rails and Ubuntu", "ra") === "<b>Ra</b>ils and Ubuntu", "highlightHtml cached query")

// Stopwords: the contractions filter nothing, so they bold only inside the
// phrase; "shell" and "well" are ordinary words.
assert(h("I don't care, don't", "dont care ") === "I <b>don&#39;t care</b>, don&#39;t", "highlightHtml a contraction stopword bolds only in the phrase")
assert(h("A shell, well", "shell ") === "A <b>shell</b>, well", "highlightHtml shell is not a stopword")
assert(h("Oh well", "well ") === "Oh <b>well</b>", "highlightHtml well is not a stopword")

// completionHtml: the typed prefix stays regular, the completion is bold.
assert(H.completionHtml("rails", "ra") === "ra<b>ils</b>", "completionHtml bolds the completion")
assert(H.completionHtml("Rails", " RA ") === "Ra<b>ils</b>", "completionHtml trims and ignores case")
assert(H.completionHtml("rails", "") === "rails", "completionHtml empty query")
assert(H.completionHtml("rails", "x") === "rails", "completionHtml query that is no prefix")
assert(H.completionHtml("a<b", "a") === "a<b>&lt;b</b>", "completionHtml escapes both parts")

console.log("test_highlight.mjs: all assertions passed")
