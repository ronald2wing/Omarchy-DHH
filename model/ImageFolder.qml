pragma ComponentBehavior: Bound
import QtQuick
import QtCore
import Quickshell.Io
import "../js/os.mjs" as Os

// The folder rendered images are saved to, ~/Pictures/dhh, made with `mkdir -p` on the first render.
Item {
  id: root

  readonly property string path: Os.fileUrlToPath(StandardPaths.writableLocation(StandardPaths.PicturesLocation)) + "/dhh"
  // The last ensure() made (or found) the folder, and no save into it has
  // failed since. A grab's saveToFile() does not create missing folders.
  readonly property bool exists: internal.exists

  // ensure() could not make the folder.
  signal failed(string message)

  // Make the folder now, whatever `exists` says; a call while one is under
  // way shares its outcome.
  function ensure() {
    if (!mkdir.running) mkdir.running = true
  }

  // A save into the folder failed: it may have been removed; the next
  // ensure() recreates it.
  function invalidate() {
    internal.exists = false
  }

  QtObject {
    id: internal
    property bool exists: false
  }

  Process {
    id: mkdir
    command: ["mkdir", "-p", root.path]
    onExited: (code) => {
      internal.exists = code === 0
      if (!internal.exists) root.failed("could not create " + root.path)
    }
  }
}
