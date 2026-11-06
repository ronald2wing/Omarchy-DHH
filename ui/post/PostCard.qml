pragma ComponentBehavior: Bound
import QtQuick
import "../base"

// One panel row around a TimelinePost: selection fill, the full-surface copy click, the divider and the "Copied" tip.
Rectangle {
  id: card

  required property var entry
  // The entry's own body, HTML-escaped with search highlights applied.
  required property string bodyHtml
  // The context author's avatar data URI from the AvatarCache ("" while
  // unsettled or after a failed fetch; the Avatar then shows the bundled
  // fallback).
  required property string contextAvatarSource
  property bool selected: false
  property bool showDivider: true
  // This card's entry is rendering: its share icon dims.
  property bool rendering: false

  signal copyRequested()
  signal renderRequested()
  signal openSourceRequested()
  signal entered()
  // Any action was taken (copy, render, open); the panel releases the
  // search field so its dropdowns close.
  signal actionTaken()

  height: post.implicitHeight
  color: card.selected ? Look.selectedRowFill : "transparent"

  // Result rows are overwritten in place as the query changes (RowLander
  // rebinds them with ListModel.set), so a card may be handed a new entry.
  onEntryChanged: {
    internal.copied = false
    copiedTimer.stop()
  }

  function showCopied() {
    internal.copied = true
    copiedTimer.restart()
  }

  function copy() {
    card.showCopied()
    card.copyRequested()
    card.actionTaken()
  }

  QtObject {
    id: internal
    // The transient "Copied" confirmation on the bookmark tooltip, restarted
    // on every copy (card body, bookmark icon, keyboard).
    property bool copied: false
    readonly property int copiedTipDuration: 1400
  }

  Timer {
    id: copiedTimer
    interval: internal.copiedTipDuration
    onTriggered: internal.copied = false
  }

  // Full-surface copy area. First child, so the post's buttons above it keep
  // their own clicks.
  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onEntered: card.entered()
    onClicked: card.copy()
  }

  TimelinePost {
    id: post
    width: parent.width
    entry: card.entry
    bodyHtml: card.bodyHtml
    contextAvatarSource: card.contextAvatarSource
    copied: internal.copied
    rendering: card.rendering
    onCopyRequested: card.copy()
    onRenderRequested: {
      card.renderRequested()
      card.actionTaken()
    }
    onOpenSourceRequested: {
      card.openSourceRequested()
      card.actionTaken()
    }
  }

  Divider {
    visible: card.showDivider
    anchors.bottom: parent.bottom
  }
}
