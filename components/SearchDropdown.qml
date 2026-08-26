import QtQuick
import qs.Commons

// Floating search dropdown surface, shared by the recent-searches and
// word-autocomplete dropdowns. Reparented into `keyCatcher` (the panel
// content root) — the panel lives in the bar's window inside an invisible
// Loader, so a dropdown parented there can never render over the separate
// layer-shell panel, and cross-window anchors never resolve. Visibility is
// purely declarative (`visible: shouldShow`) so it re-evaluates on every
// state change — no imperative open/close/refresh and no signal handler to
// fire. Geometry is a reactive binding keyed off `scrollSource.contentY` (the
// field lives inside `scrollSource`, so its keyCatcher-space position moves
// with the scroll), not a one-shot snapshot.
Rectangle {
  id: dropdown

  required property Item keyCatcher
  required property Item field
  required property Item scrollSource

  // Whether the dropdown should be shown right now; each usage site binds
  // this to its own condition (recent searches vs word autocomplete).
  property bool shouldShow: false

  // Row content supplied by the usage site (header + rows).
  default property alias content: dropdown.data

  parent: keyCatcher
  z: 100
  radius: Style.space(12)
  color: "#000000"
  visible: shouldShow

  // mapToItem is one-shot, so read scrollSource.contentY inside this binding
  // to make it re-run on every scroll — the only thing that moves the field
  // in keyCatcher space (contentX is always 0).
  readonly property point fieldBottom: {
    if (!shouldShow) return Qt.point(0, 0)
    scrollSource.contentY
    return field.mapToItem(keyCatcher, 0, field.height)
  }
  x: fieldBottom.x
  y: fieldBottom.y + Style.spacing.xxs
  width: field.width
}
