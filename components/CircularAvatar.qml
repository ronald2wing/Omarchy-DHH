import QtQuick
import QtQuick.Effects
import qs.Commons

// Circular avatar rendered via a MultiEffect mask (Rectangle+clip does not
// round the child Image in this Qt version). `size` is the diameter in
// logical px; the inner Image is loaded at 2x for retina. The white-disc mask
// lives beside the dataset assets and is resolved relative to this file, so
// callers only supply `source`/`fallbackSource`.
Item {
  id: avatar

  property int size: Style.space(40)
  required property string source
  property string fallbackSource: ""

  readonly property string maskSource: Qt.resolvedUrl("../data/avatar-mask.png")

  // A failed fetch must never leave a blank disc. `failed` latches the
  // Image.Error status; an empty `source` (missing handle) is treated the same
  // way because Qt reports it as Image.Null, not Image.Error. The effective
  // source is computed rather than assigned so the `source` binding survives
  // delegate recycling.
  property bool failed: false
  readonly property string effectiveSource: (avatar.failed || avatar.source === "")
    ? avatar.fallbackSource
    : avatar.source

  onSourceChanged: avatar.failed = false

  width: size
  height: size

  Item {
    anchors.fill: parent
    layer.enabled: true
    layer.smooth: true
    layer.effect: MultiEffect {
      maskEnabled: true
      // The mask is a plain white-disc Image (a texture source), so
      // MultiEffect samples its alpha directly. A Shape-based mask has no
      // texture of its own: it needs layer.enabled, and a hidden
      // (visible: false) layer is never rasterized, which masked the avatar
      // out entirely. The Image mask loads its texture regardless of
      // visibility and works for every avatar size via the mask stretch.
      maskSource: Image { source: avatar.maskSource }
      maskThresholdMin: 0.3
      maskSpreadAtMin: 0.3
    }

    Image {
      anchors.fill: parent
      source: avatar.effectiveSource
      sourceSize: Qt.size(avatar.size * 2, avatar.size * 2)
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      smooth: true
      onStatusChanged: {
        if (status === Image.Error) avatar.failed = true
      }
    }
  }
}
