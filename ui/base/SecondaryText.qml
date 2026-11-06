pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons

// Secondary status text in the panel chrome: XText at the shell's small body size, faded.
XText {
  opacity: Look.secondaryOpacity
  font.pixelSize: Style.font.bodySmall
}
