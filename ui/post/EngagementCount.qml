pragma ComponentBehavior: Bound
import QtQuick
import "../base"
import "../../js/format.mjs" as Format

// One engagement in a post's action row: its icon and count, lit together on hover.
Item {
  id: engagement

  // An Item, not a Row: the hover area must fill the whole stretched layout
  // slot, and a Row forbids anchors on its direct children.

  required property string icon
  required property int count
  required property string tooltip
  required property color hoverColor
  // Hover-only by default: the MouseArea takes no buttons, so clicks fall
  // through to the card's copy surface. true makes it a button.
  property bool clickable: false
  // false drops the hover and the click, for a saved image.
  property bool interactive: true
  property bool curveRendered: false

  signal clicked()

  implicitWidth: row.implicitWidth
  implicitHeight: row.implicitHeight

  Row {
    id: row
    spacing: Look.countGap
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter

    // The slot is the icon's size; the hover disc spills around it.
    Item {
      width: Look.actionIconSize
      height: Look.actionIconSize
      anchors.verticalCenter: parent.verticalCenter

      DiscButton {
        anchors.centerIn: parent
        icon: engagement.icon
        tooltip: engagement.tooltip
        hoverColor: engagement.hoverColor
        interactive: false
        highlighted: mouse.containsMouse
      }
    }

    XText {
      anchors.verticalCenter: parent.verticalCenter
      text: Format.formatEngagementCount(engagement.count)
      color: mouse.containsMouse ? engagement.hoverColor : Look.muted
      font.pixelSize: Look.captionSize
      curveRendered: engagement.curveRendered
    }
  }

  // The whole slot (icon, count and the stretch after them) shares one
  // hover and one click.
  MouseArea {
    id: mouse
    anchors.fill: parent
    enabled: engagement.interactive
    hoverEnabled: true
    cursorShape: engagement.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
    acceptedButtons: engagement.clickable ? Qt.LeftButton : Qt.NoButton
    onClicked: engagement.clicked()
  }
}
