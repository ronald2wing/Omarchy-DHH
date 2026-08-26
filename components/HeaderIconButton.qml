import QtQuick
import qs.Commons
import "."

// Header icon button: a circular hover disc behind an action icon with a
// below-centered tooltip. Shared by the back / grok / search header actions
// so their hover chrome, hit target, and tooltip can't drift apart. `source`
// is the icon URL, `tooltip` the hover label, and `clicked` fires on press.
Item {
  id: btn

  required property string source
  property size sourceSize: Qt.size(44, 44)
  required property string tooltip
  required property color panelForeground
  required property color barForeground
  required property color accentColor
  signal clicked()

  // x.com header hit target: ~34px, larger than the shell's 28px control
  // height, so the icon sits in a comfortable tap area.
  width: Style.space(34)
  height: Style.space(34)

  // Hover circle: soft light disc behind the icon (x.com header-button
  // hover), sized ~1.5x the 20px icon and centered on the hit target.
  // Declared before the icon so the icon draws on top.
  Rectangle {
    width: Style.space(34)
    height: Style.space(34)
    radius: width / 2
    anchors.centerIn: parent
    visible: mouse.containsMouse
    color: Style.hoverFillFor(barForeground, accentColor)
  }

  Image {
    width: Style.space(20)
    height: Style.space(20)
    anchors.centerIn: parent
    source: btn.source
    sourceSize: btn.sourceSize
    fillMode: Image.PreserveAspectFit
    asynchronous: true
    smooth: true
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: btn.clicked()
  }

  AccentToolTip {
    visible: mouse.containsMouse
    text: btn.tooltip
    // Qualify with `btn.`: AccentToolTip declares `barForeground`/`accentColor`
    // and inherits `panelForeground`, so an unqualified name would bind the
    // tooltip's own property to itself and loop.
    panelForeground: btn.panelForeground
    barForeground: btn.barForeground
    accentColor: btn.accentColor
  }
}
