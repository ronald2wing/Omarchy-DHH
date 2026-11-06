// Breaks a post body into lines where x.com does and gives each line x.com's width, from Chirp's measured metrics.
import { REGULAR, BOLD, EMOJI_ADVANCE, ADVANCE_LIMIT } from "./chirp-metrics.mjs"
import { unescapeHtml } from "./format.mjs"
import { WORD_CHARS } from "./words.mjs"

export { EMOJI_ADVANCE }

// One emoji (a pictograph, or a symbol asking for emoji style) with its skin
// tone and ZWJ joins. No \p{} classes: Qt's V4 parses them but never matches.
const EMOJI_RE = /(?:[\u{1F000}-\u{1FAFF}]|[\u2300-\u23FF\u2600-\u27BF\u2B00-\u2BFF]\uFE0F)(?:\uFE0F|[\u{1F3FB}-\u{1F3FF}]|\u200D(?:[\u{1F000}-\u{1FAFF}]|[\u2600-\u27BF])\uFE0F?)*/gu

// CSS fits a line when its width is at most the box's; the browser measures
// in 1/64px units, so a hair over still fits.
const FIT_SLACK = 1 / 128

// Kerning is measured between printable ASCII characters: code points below
// this.
const KERNED_RANGE = 128

// The font metrics as arrays indexed by code point (advance, NaN where
// nothing was measured) and by code-point pair (kerning), built once. A
// string key lookup in a large object is a slow scan in Qt's V4 (a
// 3,700-pair kerning object took ~43us a lookup); an array index is not.
function indexed(table) {
  const advance = new Float64Array(ADVANCE_LIMIT).fill(NaN)
  for (const c of Object.keys(table.advance)) advance[c.codePointAt(0)] = table.advance[c]
  const kerning = new Float64Array(KERNED_RANGE * KERNED_RANGE)
  for (const pair of Object.keys(table.kerning)) kerning[pair.charCodeAt(0) * KERNED_RANGE + pair.charCodeAt(1)] = table.kerning[pair]
  return { advance, kerning }
}
const REGULAR_METRICS = indexed(REGULAR)
const BOLD_METRICS = indexed(BOLD)
function metricsFor(bold) { return bold ? BOLD_METRICS : REGULAR_METRICS }
function kern(metrics, a, b) { return a < KERNED_RANGE && b < KERNED_RANGE ? metrics.kerning[a * KERNED_RANGE + b] : 0 }

// The runs of the escaped HTML PostBody takes (text plus <b> highlights), as
// [{ text, bold }] with the entities decoded.
export function htmlRuns(html) {
  const runs = []
  let bold = false
  for (const part of String(html).split(/(<\/?b>)/)) {
    if (part === "<b>") bold = true
    else if (part === "</b>") bold = false
    else if (part !== "") runs.push({ text: unescapeHtml(part), bold })
  }
  return runs
}

// Ideographs and kana break between any two characters, as in the browser.
function isIdeographic(c) {
  const code = c.codePointAt(0)
  return (code >= 0x2E80 && code <= 0x9FFF) || (code >= 0xAC00 && code <= 0xD7AF) ||
    (code >= 0xF900 && code <= 0xFAFF) || (code >= 0xFF00 && code <= 0xFFEF) || (code >= 0x20000 && code <= 0x3FFFF)
}

// One word character as search reads words, uppercase included. Spelled out
// rather than matched with the "i" flag, whose case folding would also take
// in IPA letters (an uppercase "Ɓ" is in the class, so "ɓ" would match).
const WORD_CHAR_RE = new RegExp("[A-Z" + WORD_CHARS + "]")
function isWordChar(c) { return c !== undefined && WORD_CHAR_RE.test(c) }

// A word split at its break opportunities: after a hyphen between word
// characters ("AVX-|512", "full-|time"), on either side of a dash, and
// between ideographs. A "/" is not one (URL paths stay whole).
function wordPieces(word) {
  // Most words have no break inside.
  if (!/[-\u2013\u2014\u2E80-\uFFEF\uD840-\uD8BF]/.test(word)) return [word]
  const chars = Array.from(word)
  const pieces = []
  let current = ""
  for (let i = 0; i < chars.length; i++) {
    const c = chars[i]
    if (current !== "" && (c === "\u2014" || c === "\u2013" || isIdeographic(c))) { pieces.push(current); current = "" }
    current += c
    const breakAfter = (c === "-" && isWordChar(chars[i - 1]) && isWordChar(chars[i + 1])) ||
      c === "\u2014" || c === "\u2013" || isIdeographic(c)
    if (breakAfter && i < chars.length - 1) { pieces.push(current); current = "" }
  }
  if (current !== "") pieces.push(current)
  return pieces
}

// The runs as layout tokens: { kind: "newline" | "space" | "emoji" | "word", text, bold }.
function layoutTokens(runs) {
  const tokens = []
  for (const run of runs) {
    let last = 0
    const pushText = text => {
      for (const part of text.split(/(\n| +)/)) {
        if (part === "") continue
        if (part === "\n") tokens.push({ kind: "newline", text: part, bold: run.bold })
        else if (part[0] === " ") tokens.push({ kind: "space", text: part, bold: run.bold })
        else for (const piece of wordPieces(part)) tokens.push({ kind: "word", text: piece, bold: run.bold })
      }
    }
    EMOJI_RE.lastIndex = 0
    let m
    while ((m = EMOJI_RE.exec(run.text)) !== null) {
      pushText(run.text.slice(last, m.index))
      tokens.push({ kind: "emoji", text: m[0], bold: run.bold })
      last = m.index + m[0].length
    }
    pushText(run.text.slice(last))
  }
  return tokens
}

// Chirp's width of a run of text in one weight, kerning included. A
// character it was not measured for takes `fallback(char, bold)`.
function textWidth(text, bold, fallback) {
  const metrics = metricsFor(bold)
  let width = 0
  let previous = -1
  for (let i = 0; i < text.length; i++) {
    const code = text.codePointAt(i)
    if (code > 0xFFFF) i++
    const advance = code < ADVANCE_LIMIT ? metrics.advance[code] : NaN
    width += advance === advance ? advance : fallback(String.fromCodePoint(code), bold)
    if (previous >= 0) width += kern(metrics, previous, code)
    previous = code
  }
  return width
}

// Adjacent tokens of the same kind and weight, merged into segments
// { text, bold, emoji } (an emoji segment holds one emoji).
function mergeSegments(tokens) {
  const segments = []
  for (const t of tokens) {
    const emoji = t.kind === "emoji"
    const last = segments[segments.length - 1]
    if (last && !emoji && !last.emoji && last.bold === t.bold) last.text += t.text
    else segments.push({ text: t.text, bold: t.bold, emoji })
  }
  return segments
}

// The runs laid out in `maxWidth` as x.com lays out a post body
// (white-space: pre-wrap; overflow-wrap: break-word): greedy lines, spaces
// that end a wrapped line hanging past it (and dropped), a word too wide for
// any line broken between characters. Returns [{ segments, width }], width
// being Chirp's for the line without its hanging spaces.
//
// Widths add up as the line grows: each token is measured once, and joining
// it to the line adds only the kerning across the join (kerning holds within
// one weight). Re-measuring the whole line per word cost ~80ms a post in V4.
export function layoutLines(runs, maxWidth, fallback) {
  const limit = maxWidth + FIT_SLACK
  // The stand-in font's widths, asked once per character and weight.
  const fallbackCache = {}
  const cachedFallback = (c, bold) => {
    const key = (bold ? "b" : "r") + c
    let w = fallbackCache[key]
    if (w === undefined) { w = fallback(c, bold); fallbackCache[key] = w }
    return w
  }
  const tokenWidth = token => {
    if (token.width === undefined) {
      token.width = token.kind === "emoji" ? EMOJI_ADVANCE : textWidth(token.text, token.bold, cachedFallback)
      token.first = token.text.codePointAt(0)
      token.last = token.text.codePointAt(token.text.length - 1)
    }
    return token.width
  }
  // Kerning between the end of `a` and the start of `b` (none across an
  // emoji or a change of weight).
  const kernBetween = (a, b) => {
    if (!a || a.kind === "emoji" || b.kind === "emoji" || a.bold !== b.bold) return 0
    return kern(metricsFor(a.bold), a.last, b.first)
  }

  const lines = []     // [{ tokens, width }]
  let line = []        // tokens on the current line
  let lineWidth = 0    // its width
  let pending = []     // spaces after its last word, placed only if a word follows
  let wrapped = false  // the current line began at a soft wrap
  const endLine = () => {
    lines.push({ tokens: line, width: lineWidth })
    line = []
    lineWidth = 0
    pending = []
  }
  // The line's width with `tokens` appended after it.
  const widthWith = tokens => {
    let width = lineWidth
    let previous = line[line.length - 1]
    for (const t of tokens) {
      width += tokenWidth(t) + kernBetween(previous, t)
      previous = t
    }
    return width
  }
  const append = tokens => {
    lineWidth = widthWith(tokens)
    for (const t of tokens) line.push(t)
  }
  const placeWord = token => {
    // Spaces that wrapped with the word before them hang on that line.
    if (line.length === 0) pending = []
    const candidate = pending.concat([token])
    const fitsAlone = tokenWidth(token) <= limit
    if (line.length > 0 && widthWith(candidate) <= limit) {
      append(candidate)
      pending = []
      return
    }
    if (line.length > 0) {
      endLine()
      wrapped = true
    }
    if (fitsAlone) { append([token]); return }
    // A word wider than a whole line: break it between characters.
    for (const c of Array.from(token.text)) {
      const piece = { kind: token.kind, text: c, bold: token.bold }
      if (line.length > 0 && widthWith([piece]) > limit) endLine()
      append([piece])
    }
  }
  for (const token of layoutTokens(runs)) {
    if (token.kind === "newline") {
      endLine()
      wrapped = false
    } else if (token.kind === "space") {
      // Leading spaces of a paragraph show; those at a soft wrap hang.
      if (line.length === 0 && !wrapped) append([token])
      else pending.push(token)
    } else {
      placeWord(token)
    }
  }
  endLine()
  return lines.map(l => ({ segments: mergeSegments(l.tokens), width: l.width }))
}
