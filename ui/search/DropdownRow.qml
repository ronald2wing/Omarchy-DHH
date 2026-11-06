pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import "../base"

// One dropdown row: a magnifier, a label with an optional caption, and a trailing slot.
Item {
  id: row

  // Plain `label`, or `labelHtml` for rich text.
  property string label: ""
  property string labelHtml: ""
  property string caption: ""
  default property alias trailing: trailingSlot.data

  signal clicked()

  width: parent.width
  height: Style.space(32)

  // Full-row click, under the trailing slot so its controls keep their own.
  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: row.clicked()
  }

  Icon {
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    name: "search"
  }

  Column {
    anchors.left: parent.left
    anchors.leftMargin: Style.space(32)
    anchors.right: trailingSlot.left
    anchors.rightMargin: trailingSlot.width > 0 ? Style.spacing.sm : 0
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(2)

    XText {
      width: parent.width
      text: row.labelHtml !== "" ? row.labelHtml : row.label
      textFormat: row.labelHtml !== "" ? Text.RichText : Text.PlainText
      font.pixelSize: Style.space(15)
      elide: Text.ElideRight
    }

    XText {
      width: parent.width
      visible: row.caption !== ""
      text: row.caption
      color: Look.muted
      font.pixelSize: Style.font.subtitle
      elide: Text.ElideRight
    }
  }

  Item {
    id: trailingSlot
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    width: childrenRect.width
    height: childrenRect.height
  }
}
