pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons

// An icon from assets/icons by name and size, or its `-hover` variant.
Image {
  id: icon

  required property string name
  property real size: Style.space(20)
  // Draws `<name>-hover.svg`, the variant in x.com's hover colour.
  property bool hoverVariant: false

  width: icon.size
  height: icon.size
  source: Look.icon(icon.name, icon.hoverVariant)
  // Rasterised at twice the drawn size, so it stays sharp on a scaled output.
  sourceSize: Qt.size(icon.size * 2, icon.size * 2)
  fillMode: Image.PreserveAspectFit
  asynchronous: true
  smooth: true
}
