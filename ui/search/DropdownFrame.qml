pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import "../base"

// The dropdown frame under the search field, shared by both dropdowns.
Rectangle {
  id: dropdown

  // The host declares the dropdown outside the scrolling body, so it draws
  // above it, and positions it under the field in its own coordinates. The
  // field lives inside the body, so that position moves with `scrollY`.
  required property Item field
  // The body's scroll offset.
  required property real scrollY
  property bool shown: false

  default property alias content: column.data

  z: Look.zDropdown
  radius: Style.space(12)
  color: Look.surface
  visible: dropdown.shown
  width: dropdown.field.width
  height: column.implicitHeight + Style.space(16) * 2

  x: internal.fieldBottom.x
  y: internal.fieldBottom.y + Style.spacing.xxs

  QtObject {
    id: internal
    // mapToItem is one-shot; reading scrollY inside the binding re-runs it on
    // every scroll (the body never scrolls sideways).
    readonly property point fieldBottom: {
      if (!dropdown.shown) return Qt.point(0, 0)
      dropdown.scrollY // qmllint disable confusing-expression-statement
      return dropdown.field.mapToItem(dropdown.parent, 0, dropdown.field.height)
    }
  }

  Column {
    id: column
    anchors.fill: parent
    anchors.margins: Style.space(16)
    spacing: Style.space(16)
  }
}
