pragma ComponentBehavior: Bound
import QtQuick
import "../base"

// The quotation image the renderer saves: a serif quote beside a fading portrait.
Rectangle {
  id: image

  required property var entry

  // A fixed 16:9 landscape.
  width: 600
  height: 338
  color: Look.surface
  clip: true

  QtObject {
    id: internal

    readonly property string quoteText: String(image.entry.text || "")
    readonly property int fontSize: internal.fontSizeFor(internal.quoteText.length)
    readonly property string serifFamily: "Georgia"
    readonly property color ink: "#FFFFFF"
    // The text column starts `margin` in and ends `portraitGap` short of the
    // portrait, which fills what `textShare` of the width leaves.
    readonly property real margin: 48
    readonly property real portraitGap: 24
    readonly property real textShare: 0.58
    readonly property real lineHeightRatio: 1.35
    // The attribution's size relative to the quote's.
    readonly property real attributionScale: 0.55

    // Steps down with the quote's length (UTF-16 units) so the longest fits.
    function fontSizeFor(length) {
      if (length <= 50) return 30
      if (length <= 90) return 26
      if (length <= 130) return 23
      return 20
    }
  }

  // Image-only text, so it sets its render type outright; panel text never
  // does.
  Column {
    x: internal.margin
    width: image.width * internal.textShare - internal.margin - internal.portraitGap
    anchors.verticalCenter: parent.verticalCenter
    spacing: 20

    Text {
      id: quote
      width: parent.width
      height: lineCount * lineHeight
      // Centred in each line as a browser sets it; Qt sets glyphs at the
      // line's top.
      transform: Translate { y: (quote.lineHeight - Math.ceil(quoteMetrics.height)) / 2 }
      text: "“" + internal.quoteText + "”"
      color: internal.ink
      font.family: internal.serifFamily
      font.pixelSize: internal.fontSize
      lineHeightMode: Text.FixedHeight
      lineHeight: internal.fontSize * internal.lineHeightRatio
      wrapMode: Text.Wrap
      textFormat: Text.PlainText
      renderType: Text.CurveRendering

      FontMetrics {
        id: quoteMetrics
        font: quote.font
      }
    }

    Text {
      text: Look.dhhFullName
      color: internal.ink
      font.family: internal.serifFamily
      font.italic: true
      font.pixelSize: Math.round(internal.fontSize * internal.attributionScale)
      textFormat: Text.PlainText
      renderType: Text.CurveRendering
    }
  }

  // The portrait fills the right 42%, cropped around 30% across, and melts
  // into the black on its left and bottom edges. Over a black image, black
  // gradients laid on top equal fading the portrait's own alpha.
  Item {
    x: image.width * internal.textShare
    width: image.width - x
    height: image.height
    clip: true

    Image {
      readonly property real side: Math.max(parent.width, parent.height)
      x: (parent.width - side) * 0.3
      y: (parent.height - side) * 0.5
      width: side
      height: side
      source: Look.dhhPortrait
      sourceSize: Qt.size(side * Look.imageScale, side * Look.imageScale)
      fillMode: Image.Stretch
      smooth: true
    }

    // Transparent from 32% across, solid black at the left edge.
    Rectangle {
      width: parent.width * 0.32
      height: parent.height
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0; color: Look.surface }
        GradientStop { position: 1; color: "transparent" }
      }
    }

    // Transparent down to 55%, solid black at the bottom edge.
    Rectangle {
      y: parent.height * 0.55
      width: parent.width
      height: parent.height - y
      gradient: Gradient {
        GradientStop { position: 0; color: "transparent" }
        GradientStop { position: 1; color: Look.surface }
      }
    }
  }
}
