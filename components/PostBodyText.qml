import QtQuick

// DHH's highlighted body text, shared by the plain-body path and the
// reply/repost quote card's leading body. Callers supply `text`, plus the
// theme color, font family, pixel size, and fixed line height.
Text {
  required property string fontFamily
  required property int pixelSize

  width: parent.width
  textFormat: Text.RichText
  lineHeightMode: Text.FixedHeight
  wrapMode: Text.WordWrap

  font.family: fontFamily
  font.pixelSize: pixelSize
}
