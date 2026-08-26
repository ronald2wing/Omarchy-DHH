import QtQuick
import qs.Commons

// Magnifier icon shared by the recent-search and suggestion dropdown rows.
Image {
  width: Style.space(20)
  height: Style.space(20)
  sourceSize: Qt.size(24, 24)
  fillMode: Image.PreserveAspectFit
  asynchronous: true
  smooth: true
}
