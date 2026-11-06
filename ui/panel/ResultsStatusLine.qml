pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import "../base"

// The results' status line and keyboard hint, or the centred status while no rows are in.
Column {
  id: status

  required property string text
  required property int rowCount

  spacing: Style.spacing.sm

  Row {
    width: parent.width
    spacing: Style.spacing.sm
    topPadding: Style.spacing.sm
    bottomPadding: Style.spacing.sm

    SecondaryText {
      id: statusLine
      visible: status.rowCount > 0
      width: Math.min(Style.space(260), implicitWidth)
      text: status.text
      elide: Text.ElideRight
    }

    Item {
      width: Math.max(0, parent.width - (statusLine.visible ? statusLine.width + Style.spacing.sm : 0) - keyboardHint.implicitWidth - Style.spacing.sm)
      height: 1
    }

    SecondaryText {
      id: keyboardHint
      text: status.rowCount > 0 ? "↑ ↓ navigate · Enter copy" : ""
    }
  }

  Item {
    width: parent.width
    height: Style.space(96)
    visible: status.rowCount === 0

    SecondaryText {
      anchors.centerIn: parent
      text: status.text
      font.pixelSize: Style.font.body
    }
  }
}
