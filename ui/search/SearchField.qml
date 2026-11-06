pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as QQC
import Quickshell
import qs.Commons
import "../base"

// x.com's search pill: magnifier, the single clipboard-safe TextArea editor, clear button.
Item {
  id: field

  // Mirrors the editor both ways; `edited` fires only for user input, not
  // for a programmatic fill from a dropdown row.
  property alias text: editor.text
  // Longest query, in UTF-16 units: enough for any phrase, small enough
  // that the highlight pattern and the persisted recent-search stay cheap.
  readonly property int maxLength: 256
  readonly property bool hasFocus: editor.activeFocus
  // Arrow keys move the result selection only while results are showing.
  property bool navigable: false

  signal edited()
  signal moveRequested(int delta)
  // Escape: the host takes the focus away from the field.
  signal leaveRequested()

  function focusEditor() { editor.forceActiveFocus() }
  function blurEditor() { editor.focus = false }

  // `s` cut to maxLength, never leaving half a surrogate pair at the end.
  function clampQuery(s) {
    let out = s.slice(0, field.maxLength)
    const tail = out.charCodeAt(out.length - 1)
    if (tail >= 0xD800 && tail <= 0xDBFF) out = out.slice(0, -1)
    return out
  }

  // `s` with each run of line breaks as one space, every other character as
  // typed. The onTextChanged backstop runs on every edit, typing included,
  // so it must not collapse or trim spaces: trimming would eat the space
  // typed before the next word.
  function flattenLineBreaks(s) {
    return s.replace(/[\r\n\u2028\u2029]+/g, " ")
  }

  // Pasted `s` as one line: each whitespace run (tabs and line breaks
  // included) becomes one space and the ends are trimmed. A paste drops in
  // a whole chunk of someone else's text, so its layout whitespace goes.
  function flattenPaste(s) {
    return s.replace(/\s+/g, " ").trim()
  }

  width: parent.width
  height: Style.space(38)

  // A TextArea, not a TextField: Qt 6.12's TextInput canPaste path reads the
  // full clipboard text on every clipboard change (an unsolicited, unbounded
  // Wayland read inside the shared shell), while TextEdit-derived controls
  // check offered formats only. Return and paste handling below keep the
  // query single-line, and onTextChanged bounds it whatever path the text
  // took in (typing, Ctrl+V, a middle-click primary selection paste, the
  // context menu).
  QQC.TextArea {
    id: editor
    anchors.fill: parent
    placeholderText: "Search"
    wrapMode: QQC.TextArea.NoWrap
    clip: true
    color: Look.themeText
    selectionColor: Look.textSelectionColor
    selectedTextColor: Look.themeText
    placeholderTextColor: Util.alpha(Look.barForeground, 0.5)
    leftPadding: Style.space(44)
    rightPadding: Style.space(16)
    topPadding: Style.space(11)
    bottomPadding: Style.space(11)
    font.family: Look.fontFamily
    font.letterSpacing: Look.letterSpacingFor(Font.Normal)
    font.pixelSize: Style.space(15)
    font.weight: Font.Normal

    // Subtle theme-aware fill with a 1px muted ring, accent on focus.
    background: Rectangle {
      radius: height / 2
      color: Util.alpha(Look.barForeground, 0.08)
      border.width: Look.hairline
      border.color: editor.activeFocus ? Look.accent : Look.mutedBorder
    }

    onTextEdited: field.edited()

    // Backstop for every edit path the paste handler does not see: line
    // breaks become spaces and the text is cut at maxLength, so a
    // middle-click paste of a whole document cannot become the query.
    onTextChanged: {
      const clamped = field.clampQuery(field.flattenLineBreaks(editor.text))
      if (clamped === editor.text) return
      const cursor = Math.min(editor.cursorPosition, clamped.length)
      editor.text = clamped
      editor.cursorPosition = cursor
      field.edited()
    }

    // Paste runs on the explicit gesture only: the text is flattened and
    // capped so the query stays single-line.
    function pasteSingleLine() {
      const flat = field.clampQuery(field.flattenPaste(Quickshell.clipboardText || ""))
      if (flat === "") return
      const from = Math.min(selectionStart, selectionEnd)
      remove(from, Math.max(selectionStart, selectionEnd))
      insert(from, flat)
      cursorPosition = from + flat.length
      field.edited()
    }

    Keys.priority: Keys.BeforeItem
    Keys.onPressed: (event) => {
      if (event.matches(StandardKey.Paste)) {
        editor.pasteSingleLine()
        event.accepted = true
        return
      }
      if (!field.navigable) return
      if (event.key === Qt.Key_Down) { field.moveRequested(1); event.accepted = true }
      else if (event.key === Qt.Key_Up) { field.moveRequested(-1); event.accepted = true }
    }
    // Return/Enter never insert a newline; IME commits pass through.
    Keys.onReturnPressed: (event) => { if (!editor.inputMethodComposing) event.accepted = true }
    Keys.onEnterPressed: (event) => { if (!editor.inputMethodComposing) event.accepted = true }
    Keys.onEscapePressed: field.leaveRequested()
  }

  Icon {
    anchors.left: parent.left
    anchors.leftMargin: Style.space(16)
    anchors.verticalCenter: parent.verticalCenter
    name: "search"
    size: Style.space(16)
    opacity: Look.secondaryOpacity
  }

  // x.com's clear button: a black "×" on a white disc about half the field's
  // height, 16px from the right edge.
  Rectangle {
    anchors.right: parent.right
    anchors.rightMargin: Style.space(16)
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(17)
    height: Style.space(17)
    radius: width / 2
    visible: editor.text !== ""
    color: Look.clearButtonFill

    Icon {
      anchors.centerIn: parent
      name: "xmark-dark"
      size: Style.space(11)
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        editor.text = ""
        field.edited()
        editor.forceActiveFocus()
      }
    }
  }
}
