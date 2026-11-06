pragma ComponentBehavior: Bound
import QtQuick

// x.com's hairline rule across its parent's width.
Rectangle {
  width: parent.width
  height: Look.hairline
  // Solid x.com divider grey: an alpha-blended foreground vanished against
  // the themed panel background.
  color: Look.divider
}
