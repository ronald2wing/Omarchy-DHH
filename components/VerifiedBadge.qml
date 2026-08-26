import QtQuick

// X verified seal + 37signals logo pair, vertically centered on the
// author/name line. Shared by the result-row author line and the header
// identity block. `size` sizes the seal; `logoSize` sizes the mark — they
// differ by a pixel in the compact row, match in the header. The seal→logo
// gap mirrors the hosting Row's `spacing`.
Item {
  required property int size
  property int logoSize: size
  property bool showLogo: true
  required property string badgeSource
  required property string logoSource
  required property color borderColor

  readonly property int gap: parent.spacing
  readonly property int totalWidth: showLogo ? size + gap + logoSize : size

  width: totalWidth
  height: Math.max(size, logoSize)

  // Solid X verified seal (blue circle + white checkmark) matching the
  // render's badge SVG.
  Image {
    id: verifiedBadge
    width: size
    height: size
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    source: badgeSource
    sourceSize: Qt.size(size * 2, size * 2)
    fillMode: Image.PreserveAspectFit
    asynchronous: true
    smooth: true
  }

  // 37signals company logo beside the blue verified check. A thin (1px)
  // sharp-corner square border flush against the logo edge.
  Rectangle {
    visible: showLogo
    width: logoSize
    height: logoSize
    anchors.left: verifiedBadge.right
    anchors.leftMargin: gap
    anchors.verticalCenter: parent.verticalCenter
    color: "transparent"
    border.width: 1
    border.color: borderColor

    Image {
      anchors.fill: parent
      source: logoSource
      sourceSize: Qt.size(32, 32)
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      smooth: true
    }
  }
}
