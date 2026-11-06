pragma ComponentBehavior: Bound
import QtQuick

// Plain text in x.com's type: Adwaita Sans standing in for Chirp at 15px, letter-spaced by weight, in the theme's text colour.
Text {
  id: label

  // The weight, set here rather than on `font` so the letter spacing can
  // follow it (Look.letterSpacingFor).
  property int weight: Font.Normal
  // Curve-rendered so glyph outlines stay exact when the renderer grabs at
  // Look.imageScale. Panel text leaves Qt's default render type.
  property bool curveRendered: false

  font.family: Look.fontFamily
  font.pixelSize: Look.textSize
  font.weight: label.weight
  font.letterSpacing: Look.letterSpacingFor(label.weight)
  color: Look.themeText
  textFormat: Text.PlainText

  Binding on renderType {
    when: label.curveRendered
    value: Text.CurveRendering
  }
}
