pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "../js/entries.mjs" as Entries

// The browser, the file manager and the clipboard: every program the panel starts detached, and every clipboard write.
QtObject {
  // Only http(s) URLs: an entry's source never reaches xdg-open as a file,
  // a scheme handler or an option.
  function openUrl(url) {
    if (!Entries.isHttpUrl(url)) return
    Quickshell.execDetached(["xdg-open", url])
  }

  function openPath(path) {
    Quickshell.execDetached(["xdg-open", path])
  }

  function copyText(text) {
    Quickshell.clipboardText = text
  }

  // wl-copy forks a daemon that serves the clipboard; detached, so it never
  // holds the shell's pipes. The file is an argument, never code.
  function copyImageFile(path) {
    Quickshell.execDetached(["sh", "-c", "exec wl-copy --type image/png < \"$1\"", "sh", path])
  }
}
