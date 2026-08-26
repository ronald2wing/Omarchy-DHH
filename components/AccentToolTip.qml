import QtQuick
import qs.Commons
import "."

// Accent-tinted tooltip for the header and folder hover buttons: the themed
// CenteredToolTip with the hover-disc accent background and X-text foreground.
// `text`, `visible`, and `panelForeground` are inherited from PanelToolTip and
// set by the caller.
CenteredToolTip {
  required property color barForeground
  required property color accentColor

  background: Rectangle {
    color: Style.hoverFillFor(barForeground, accentColor)
    radius: 9999
  }
}
