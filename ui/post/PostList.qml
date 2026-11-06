pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import "../base"
import "../../model"
import "../../js/entries.mjs" as Entries

// A list of PostCards over a row model, under a hairline; the host sets its width.
Column {
  id: list

  required property AvatarCache avatars
  required property ListModel model
  // Index of the keyboard/hover-selected row; -1 for none.
  property int selectedIndex: -1
  // Content key of the entry currently rendering, dimming that card's share
  // icon; "" when idle.
  property string renderingKey: ""

  signal copyRequested(var entry)
  signal renderRequested(var entry)
  signal openSourceRequested(var entry)
  signal entered(int index)
  // A card's action was taken (copy, render, open).
  signal actionTaken()

  // The card at `index`, or null while it is not built.
  function cardAt(index) {
    return listView.itemAtIndex(index) as PostCard
  }

  // The card at `index` shows its "Copied" tip, for a copy made from the
  // keyboard, which has no hover.
  function showCopiedAt(index) {
    const card = list.cardAt(index)
    if (card) card.showCopied()
  }

  spacing: Style.spacing.xxs

  Divider {}

  // Sized to its content and never scrolled itself: the panel body owns the
  // scrolling. The Column around it lets `visible` collapse the list out of
  // the layout.
  ListView {
    id: listView
    width: parent.width
    height: Math.max(Style.space(96), contentHeight)
    clip: true
    model: list.model
    interactive: false

    delegate: PostCard {
      id: card
      required property int index

      width: listView.width
      selected: list.selectedIndex === card.index
      showDivider: card.index < listView.count - 1
      rendering: list.renderingKey !== "" && Entries.contentKey(card.entry) === list.renderingKey
      contextAvatarSource: list.avatars.contextAvatarFor(card.entry)

      onCopyRequested: list.copyRequested(card.entry)
      onRenderRequested: list.renderRequested(card.entry)
      onOpenSourceRequested: list.openSourceRequested(card.entry)
      onEntered: list.entered(card.index)
      onActionTaken: list.actionTaken()
    }
  }
}
