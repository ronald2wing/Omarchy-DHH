pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects

// A circular avatar that falls back to Look.fallbackAvatar.
Item {
  id: avatar

  required property real size
  required property string source
  // false skips the mask layer for a source that is already a circular PNG
  // with alpha, such as the bundled DHH avatar.
  property bool masked: true
  // Device pixels per avatar pixel; a saved image passes Look.imageScale.
  property real pixelRatio: Screen.devicePixelRatio

  width: avatar.size
  height: avatar.size

  // A failed load must never leave a blank disc. `loadFailed` latches
  // Image.Error; an empty source (no handle) falls back the same way, since
  // Qt reports it as Image.Null. Computed, not assigned, so the binding
  // survives delegate recycling.
  QtObject {
    id: internal
    property bool loadFailed: false
    readonly property string shownSource: (internal.loadFailed || avatar.source === "") ? Look.fallbackAvatar : avatar.source
  }

  onSourceChanged: internal.loadFailed = false

  // Rounded by a MultiEffect mask: Rectangle + clip does not round a child
  // Image.
  Item {
    anchors.fill: parent
    layer.enabled: avatar.masked
    layer.smooth: true
    layer.textureSize: Qt.size(avatar.size * avatar.pixelRatio, avatar.size * avatar.pixelRatio)
    layer.effect: MultiEffect {
      maskEnabled: true
      // A plain white-disc Image is a texture source MultiEffect can sample
      // at any size; a Shape mask has no texture until it is rasterized.
      maskSource: Image { source: Look.avatarMask }
      maskThresholdMin: 0.3
      maskSpreadAtMin: 0.3
    }

    Image {
      anchors.fill: parent
      source: internal.shownSource
      sourceSize: Qt.size(avatar.size * avatar.pixelRatio, avatar.size * avatar.pixelRatio)
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      smooth: true
      onStatusChanged: { if (status === Image.Error) internal.loadFailed = true }
    }
  }
}
