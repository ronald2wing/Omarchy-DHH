pragma ComponentBehavior: Bound
import QtQuick
import "../base"
import "../../model"
import "../../js/entries.mjs" as Entries
import "../../js/rendered-image.mjs" as RenderedImage

// Renders an entry as a PNG in the image folder and copies it to the clipboard, one at a time.
Item {
  id: root

  // Both images are drawn off to the side of the panel and grabbed at
  // Look.imageScale: grabToImage needs an item in a shown window, so the
  // renderer lives in the panel body. They stay built, hidden between
  // renders, so their Image items decode once.

  required property AvatarCache avatars
  required property ImageFolder imageFolder

  readonly property bool busy: internal.entry !== null
  // Content key of the entry being rendered, so its panel card can dim its
  // share icon; "" when idle.
  readonly property string renderingKey: internal.entry ? Entries.contentKey(internal.entry) : ""
  // Path of the last rendered image; "" until the first render succeeds.
  readonly property string imagePath: internal.imagePath

  signal failed(string message)

  x: -postImage.width - 64

  function render(entry) {
    if (root.busy || !entry || String(entry.text || "") === "") return
    internal.entry = entry
    watchdog.restart()
    // A context author's avatar the panel has not fetched yet: ask for it
    // and wait until its fetch finishes (a failed fetch finishes too).
    if (root.avatars.awaitsFetch(entry)) root.avatars.request([entry])
    else internal.draw()
  }

  QtObject {
    id: internal

    // The entry being rendered, and the one the images show (the last
    // rendered, so they never bind to null).
    property var entry: null
    property var shownEntry: ({ type: "post", text: "" })
    readonly property Item image: RenderedImage.rendersAsPostImage(internal.shownEntry) ? postImage : quotationImage
    property bool drawing: false
    // Frames the window has drawn since the entry was shown. Qt lays an image
    // out while preparing a frame, so its size is only final after one; two,
    // since a frame already under way when the entry changed does not count.
    property int framesSinceShown: 0
    property string imagePath: ""
    // A grab is under way (between grabToImage and its callback).
    property bool grabbing: false

    // Show the entry and grab it once its Image items have loaded and the
    // folder exists.
    function draw() {
      if (!internal.entry || internal.drawing) return
      internal.shownEntry = internal.entry
      internal.framesSinceShown = 0
      internal.grabbing = false
      internal.drawing = true
      if (!root.imageFolder.exists) root.imageFolder.ensure()
    }

    // Grab once the folder exists, the image is laid out and every Image item
    // in it has loaded.
    function grabIfReady() {
      if (!root.imageFolder.exists || internal.framesSinceShown < 2 || internal.hasLoadingImage(internal.image)) return
      internal.grab()
    }

    function finish(path) {
      watchdog.stop()
      internal.drawing = false
      internal.grabbing = false
      internal.entry = null
      if (path === "") return
      // Same path after a re-render: clear first so the preview reloads.
      internal.imagePath = ""
      internal.imagePath = path
    }

    function fail(message) {
      internal.finish("")
      root.failed(message)
    }

    function grab() {
      const image = internal.image
      // grabToImage scales its target size by the window's scale (1.25 on a
      // fractionally scaled output, where Screen reports 2); the image is
      // Look.imageScale everywhere.
      const window = root.Window.window
      const factor = Look.imageScale / (window && window.devicePixelRatio > 0 ? window.devicePixelRatio : 1)
      const path = root.imageFolder.path + "/" + RenderedImage.imageFileName(internal.entry)
      internal.grabbing = true
      const started = image.grabToImage(result => {
        if (!internal.entry) return
        if (!result.saveToFile(path)) {
          root.imageFolder.invalidate()
          internal.fail("Render failed: could not save " + path)
          return
        }
        Desktop.copyImageFile(path)
        internal.finish(path)
      }, Qt.size(Math.round(image.width * factor), Math.round(image.height * factor)))
      if (!started) internal.fail("Render failed")
    }

    // Whether `item` or any item under it is an Image still loading.
    function hasLoadingImage(item) {
      if (item instanceof Image && item.status === Image.Loading) return true
      for (let i = 0; i < item.children.length; i++) {
        if (internal.hasLoadingImage(item.children[i])) return true
      }
      return false
    }
  }

  Connections {
    target: root.avatars
    function onSettled() {
      if (internal.entry && !root.avatars.awaitsFetch(internal.entry)) internal.draw()
    }
  }

  Connections {
    target: root.imageFolder
    function onFailed(message) {
      if (internal.entry) internal.fail("Render failed: " + message)
    }
  }

  // Drives frames while drawing, counting them, and grabs on the first one
  // where the image is laid out, its Image items have loaded and the folder
  // exists.
  FrameAnimation {
    running: internal.drawing && !internal.grabbing
    onTriggered: {
      internal.framesSinceShown++
      internal.grabIfReady()
    }
  }

  // An avatar that never arrives, a folder that never appears, or a grab
  // that never answers (the panel closed mid-render) must not wedge the
  // renderer.
  Timer {
    id: watchdog
    interval: 8000
    onTriggered: internal.fail("Render timed out")
  }

  PostImage {
    id: postImage
    visible: internal.drawing && internal.image === postImage
    entry: internal.shownEntry
    contextAvatarSource: root.avatars.contextAvatarFor(internal.shownEntry)
  }

  QuotationImage {
    id: quotationImage
    visible: internal.drawing && internal.image === quotationImage
    entry: internal.shownEntry
  }
}
