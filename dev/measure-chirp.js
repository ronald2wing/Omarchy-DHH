// Paste into DevTools (F12, Console) on an x.com page showing a post with an
// emoji. Measures Chirp's advances and kerning (regular and bold, 15px), the
// emoji's width and margins, and the widths of a few check lines, and
// downloads them as xcom-metrics.json, from which
// dev/generate-chirp-metrics.mjs writes js/chirp-metrics.mjs and
// tests/js/chirp-check-lines.json. Reads the page only; sends nothing
// anywhere.
(() => { try {
  const body = document.querySelector('[data-testid="tweetText"]')
  const family = body ? getComputedStyle(body).fontFamily : 'TwitterChirp, sans-serif'
  const ctx = document.createElement("canvas").getContext("2d")
  ctx.fontKerning = "normal"
  const chars = []
  for (let c = 0x20; c < 0x7f; c++) chars.push(String.fromCharCode(c))
  // Common non-ASCII characters in posts.
  for (const c of "·…–—‘’“”•×÷°€£¥©®™¿¡àáâäãåæçèéêëìíîïñòóôöõøùúûüýÿßÀÁÂÄÇÉÈÊËÍÎÏÑÓÔÖØÚÜ←→↑↓✓✔") chars.push(c)
  const result = { weights: {} }
  for (const weight of [400, 700]) {
    ctx.font = `${weight} 15px ${family}`
    const adv = {}
    for (const c of chars) adv[c] = +ctx.measureText(c).width.toFixed(3)
    const kern = {}
    const ascii = chars.filter(c => c.charCodeAt(0) < 0x7f)
    for (const a of ascii) for (const b of ascii) {
      const k = ctx.measureText(a + b).width - adv[a] - adv[b]
      if (Math.abs(k) >= 0.005) kern[a + b] = +k.toFixed(3)
    }
    result.weights[weight] = { adv, kern }
  }
  // An emoji as x.com draws it in a post body (an <img> sized in em).
  const emoji = document.querySelector('[data-testid="tweetText"] img')
  if (emoji) {
    const cs = getComputedStyle(emoji)
    result.emoji = { width: emoji.getBoundingClientRect().width, marginLeft: cs.marginLeft, marginRight: cs.marginRight }
  }
  // Check lines: the widths the browser lays out for real DOM text.
  const span = document.createElement("span")
  span.style.cssText = `position:absolute;visibility:hidden;white-space:pre;font:400 15px/20px ${family}`
  document.body.appendChild(span)
  result.check = {}
  for (const t of ["It really is full circle that the man partly responsible for bringing me to Linux",
                   "It really is full circle that the man partly responsible for bringing me to",
                   "is now spearheading automated QA for Omarchy. Love this man!",
                   "Working on Omarchy Automation.  Brownbaggin, Teabaggin, Lunabaggin,"]) {
    span.textContent = t
    result.check[t] = +span.getBoundingClientRect().width.toFixed(3)
  }
  span.remove()
  const a = document.createElement("a")
  a.href = URL.createObjectURL(new Blob([JSON.stringify(result)], { type: "application/json" }))
  a.download = "xcom-metrics.json"
  document.body.appendChild(a); a.click(); a.remove()
  console.log("%cSaved xcom-metrics.json to Downloads", "color:#1d9bf0;font-weight:bold", Object.keys(result.weights[400].kern).length, "kerning pairs")
} catch (e) { console.error("measure-chirp failed:", e) } })()
