pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../base"

// x.com's unfollow confirmation over the whole panel; it only flips the header's Following pill.
Rectangle {
  id: dialog

  // The host owns `shown`; every exit path emits one of the signals.
  property bool shown: false

  signal confirmed()
  signal canceled()

  // Fills the panel, so it dims the header and body too.
  anchors.fill: parent
  visible: dialog.shown
  z: Look.zModal
  // The scrim's dim rides on its own colour alpha, not `opacity`, which would
  // wash out the dialog box drawn above it.
  color: Look.modalScrim

  // Scrim click cancels; the dialog box swallows its own clicks below.
  MouseArea {
    anchors.fill: parent
    onClicked: dialog.canceled()
  }

  // Takes keyboard focus while shown so typing cannot leak to the search field
  // behind the modal. Escape rides a window-wide Shortcut: the panel's key
  // catcher can steal active focus, which defeats a Keys handler here.
  FocusScope {
    anchors.fill: parent
    focus: dialog.shown

    Shortcut {
      enabled: dialog.shown
      sequence: "Escape"
      onActivated: dialog.canceled()
    }
  }

  Rectangle {
    anchors.centerIn: parent
    width: Style.space(320)
    height: column.implicitHeight + Style.space(24) * 2
    radius: Style.space(16)
    color: Look.surface

    MouseArea { anchors.fill: parent }

    ColumnLayout {
      id: column
      anchors.fill: parent
      anchors.margins: Style.space(24)
      spacing: Style.space(16)

      XText {
        Layout.fillWidth: true
        text: "Unfollow " + Look.dhhHandle + "?"
        color: Look.surfaceText
        font.pixelSize: Look.titleSize
        weight: Font.Bold
        wrapMode: Text.WordWrap
      }

      XText {
        Layout.fillWidth: true
        text: "Their posts will no longer show up in your Following timeline. You can still view their profile, unless their posts are protected."
        color: Look.muted
        wrapMode: Text.WordWrap
      }

      PillButton {
        Layout.fillWidth: true
        label: "Unfollow"
        primary: true
        onClicked: dialog.confirmed()
      }

      PillButton {
        Layout.fillWidth: true
        label: "Cancel"
        onClicked: dialog.canceled()
      }
    }
  }
}
