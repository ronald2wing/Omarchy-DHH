pragma ComponentBehavior: Bound
import QtQuick
import "../base"
import "../../js/line-layout.mjs" as LineLayout
import "../../js/format.mjs" as Format

// A post body as x.com sets it: 15px on a 20px line, broken where x.com breaks it and each line as wide as x.com's.
Text {
  id: body

  // The body as HTML: escaped text, optionally with <b> highlights. The
  // caller sets the width the lines break in.
  required property string html
  // Curve-rendered, as XText's: a saved image's text stays exact when the
  // renderer grabs it at Look.imageScale; panel text keeps Qt's default.
  property bool curveRendered: false

  // The lines as x.com lays them out in this width, from Chirp's measured
  // metrics (js/line-layout.mjs); a character Chirp was not measured for
  // takes the stand-in font's width. A body not yet given its width (0, or
  // less while the widths above it settle during creation) takes none:
  // breaking there put every character on its own line, and building those
  // lines' rich text cost most of a card's creation time.
  readonly property var lines: body.html === "" || body.width <= 0 ? [] : LineLayout.layoutLines(LineLayout.htmlRuns(body.html), body.width,
    (c, bold) => (bold ? boldMetrics : regularMetrics).advanceWidth(c) + Look.letterSpacingFor(bold ? Font.Bold : Font.Normal))

  // Exactly the lines, as in CSS; an empty body takes none.
  height: body.lines.length * Look.bodyLineHeight
  // The lines are already broken; Qt only stacks them.
  text: "<div style=\"white-space:pre\">" + body.lines.map(line => internal.lineHtml(line)).join("<br>") + "</div>"
  textFormat: Text.RichText
  wrapMode: Text.NoWrap
  font.family: Look.fontFamily
  font.pixelSize: Look.textSize
  color: Look.themeText
  lineHeightMode: Text.FixedHeight
  lineHeight: Look.bodyLineHeight
  // Centred in each line as a browser sets it; Qt sets glyphs at the line's
  // top.
  transform: Translate { y: (Look.bodyLineHeight - Math.ceil(regularMetrics.height)) / 2 }

  Binding on renderType {
    when: body.curveRendered
    value: Text.CurveRendering
  }

  QtObject {
    id: internal

    // One line as rich text. Its letters close up or open out by the same
    // amount so the line ends where x.com's does, whatever the stand-in font's
    // widths. An emoji keeps x.com's 20.25px: Noto Color Emoji at 20px draws
    // about as large (17px of ink to x.com's 17.6px) but advances 21.25px, and
    // its sizes snap in steps, so it is closed up by 1px.
    function lineHtml(line) {
      let natural = 0
      let letters = 0
      for (const s of line.segments) {
        if (s.emoji) {
          natural += LineLayout.EMOJI_ADVANCE
        } else {
          natural += (s.bold ? boldMetrics : regularMetrics).advanceWidth(s.text)
          letters += Array.from(s.text).length
        }
      }
      const spacing = letters > 0 ? (line.width - natural) / letters : 0
      return line.segments.map(s => s.emoji
        ? "<span style=\"font-size:20px;letter-spacing:-1px\">" + s.text + "</span>"
        : "<span style=\"letter-spacing:" + spacing.toFixed(3) + "px" + (s.bold ? ";font-weight:bold" : "") + "\">" + Format.escapeHtml(s.text) + "</span>").join("")
    }
  }

  FontMetrics {
    id: regularMetrics
    font.family: Look.fontFamily
    font.pixelSize: Look.textSize
  }

  FontMetrics {
    id: boldMetrics
    font.family: Look.fontFamily
    font.pixelSize: Look.textSize
    font.weight: Font.Bold
  }
}
