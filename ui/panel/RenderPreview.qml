pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import "../base"

// Preview of the last rendered image, with a status line and an open-folder button.
Column {
  id: preview

  required property string imagePath

  signal openFolderRequested()

  visible: preview.imagePath !== ""
  spacing: Style.spacing.xxs

  MouseArea {
    width: parent.width
    height: image.height
    cursorShape: Qt.PointingHandCursor
    onClicked: preview.openFolderRequested()

    Image {
      id: image
      width: parent.width
      source: Util.fileUrl(preview.imagePath)
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      // A re-render overwrites the same file.
      cache: false
      smooth: true
      // Fit the width, keep the aspect ratio, cap the height so a tall entry
      // cannot push the panel off-screen. sourceSize is 0x0 until the image
      // has loaded.
      height: image.sourceSize.width > 0
        ? Math.min(Style.space(240), image.sourceSize.height * (image.width / image.sourceSize.width))
        : Style.space(160)
    }
  }

  Row {
    width: parent.width
    spacing: Style.spacing.md

    SecondaryText {
      width: parent.width - Style.spacing.controlHeight - Style.spacing.md
      anchors.verticalCenter: parent.verticalCenter
      text: "Saved · Copied to clipboard"
      elide: Text.ElideRight
    }

    DiscButton {
      anchors.verticalCenter: parent.verticalCenter
      diameter: Style.spacing.controlHeight
      icon: "folder"
      tooltip: "Open folder"
      tooltipAccent: true
      onClicked: preview.openFolderRequested()
    }
  }
}
