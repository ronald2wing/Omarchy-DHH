pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import "../base"

// The recent-searches dropdown: remembered queries with forget and clear.
DropdownFrame {
  id: dropdown

  required property var queries

  signal querySelected(string query)
  signal forgetRequested(string query)
  signal clearRequested()

  Item {
    width: parent.width
    height: Style.space(24)

    XText {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: "Recent"
      font.pixelSize: Style.space(15)
      weight: Font.Bold
    }

    XText {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: "Clear all"
      color: Look.accent
      font.pixelSize: Style.space(15)

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: dropdown.clearRequested()
      }
    }
  }

  Repeater {
    model: dropdown.queries

    delegate: DropdownRow {
      id: row
      required property string modelData

      label: row.modelData
      onClicked: dropdown.querySelected(row.modelData)

      Item {
        width: Style.space(28)
        height: Style.space(28)

        Icon {
          anchors.centerIn: parent
          name: "xmark-accent"
          size: Style.space(18)
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: dropdown.forgetRequested(row.modelData)
        }
      }
    }
  }
}
