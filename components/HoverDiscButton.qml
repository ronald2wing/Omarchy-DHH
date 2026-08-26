import QtQuick
import qs.Commons
import "."

// Circular 34.75px hover-disc action button (X-style). Shared by the
// author-line Grok + "..." cluster and the bottom bookmark/share pair: a
// circular hover disc that appears on hover, a centered action icon with a
// resting→hover source swap, a full-fill MouseArea, and a centered tooltip
// below. `iconOpacity` dims the icon in place (used by the share button
// while a render is in flight).
Item {
  id: disc

  required property string icon
  required property string iconHover
  required property size iconSourceSize
  required property string tooltip
  property real iconOpacity: 1.0
  // Forces the tooltip visible without hover, so a copy triggered by a
  // card-body click or the keyboard still surfaces its "Copied" confirmation.
  property bool tooltipForced: false
  required property real iconSize
  required property color barForeground
  required property color accentColor
  required property string fontFamily
  signal clicked()

  width: Style.spaceReal(34.75)
  height: Style.spaceReal(34.75)

  // Circular hover disc behind the icon, matching the stat icons' chrome.
  Rectangle {
    anchors.fill: parent
    radius: width / 2
    visible: discMouse.containsMouse
    color: Style.hoverFillFor(barForeground, accentColor)
  }

  Image {
    anchors.centerIn: parent
    width: iconSize
    height: iconSize
    source: discMouse.containsMouse ? iconHover : icon
    sourceSize: iconSourceSize
    fillMode: Image.PreserveAspectFit
    asynchronous: true
    smooth: true
    opacity: iconOpacity
  }

  MouseArea {
    id: discMouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: disc.clicked()
  }

  CenteredToolTip {
    visible: discMouse.containsMouse || disc.tooltipForced
    text: tooltip
    // Qualify with `disc.`: the tooltip inherits `fontFamily`, so an
    // unqualified name would bind the tooltip's own property to itself.
    fontFamily: disc.fontFamily
    fontSize: Style.font.body
  }
}
