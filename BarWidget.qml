pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui
import "model"
import "ui/base"
import "ui/panel"

// Entry point: the bar glyph and the panel host; creates and wires the model objects.
Panel {
  id: root
  moduleName: "dhh"
  // The Panel owns the open state (`opened`) and this IPC target:
  // open/close/show/hide/toggle.
  ipcTarget: "dhh"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // The model objects live here, not in the panel body (built on the first
  // open), so their state loads with the bar and outlives the panel's
  // visibility. Each one that works on open binds `active` to the open state
  // and starts or cancels that work itself.
  //
  // Held in properties rather than ids: an id named like PanelBody's
  // matching property shadows it (qmllint's id-shadows-member).
  readonly property Dataset dataset: Dataset { active: root.opened }
  readonly property History history: History { dataset: root.dataset }
  readonly property RecentSearches recentSearches: RecentSearches {}
  readonly property PostCount postCount: PostCount { active: root.opened }
  readonly property AvatarCache avatars: AvatarCache { active: root.opened; requestOnOpen: root.history.entries }
  readonly property ImageFolder imageFolder: ImageFolder {}

  // Look is one singleton for every monitor's instance; each writes the same
  // value (Panel.barForeground is the bar's, else Color.foreground).
  // Assigned rather than bound, so a monitor going away does not restore an
  // old value the way a destroyed Binding would.
  Component.onCompleted: Look.barForeground = root.barForeground
  onBarForegroundChanged: Look.barForeground = root.barForeground

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: "DHH quotes & X posts"
    foreground: root.barForeground
    iconComponent: Component {
      Image {
        anchors.centerIn: parent
        // The glyph's drawn size: the square SVG fits this width, 7/8 of the
        // body font size.
        width: Style.font.body * 7 / 8
        height: Style.font.body
        source: Look.icon("bar-glyph")
        sourceSize: Qt.size(24, 24)
        fillMode: Image.PreserveAspectFit
        smooth: true
      }
    }
    onPressed: (mouseButton) => { if (mouseButton === Qt.LeftButton) root.toggle() }
  }

  KeyboardPanel {
    id: keyboardPanel
    padding: 0
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyboardPanel.loadedContent
    contentWidth: keyboardPanel.fittedContentWidth(Look.columnWidth)
    contentHeight: keyboardPanel.fittedContentHeight(keyboardPanel.loadedContentHeight, Style.space(640))
    borderSpec: Border.flat(Look.divider, Look.panelBorderWidth)

    content: Component {
      PanelBody {
        dataset: root.dataset
        history: root.history
        recentSearches: root.recentSearches
        postCount: root.postCount
        avatars: root.avatars
        imageFolder: root.imageFolder
        opened: root.opened
        onCloseRequested: root.close()
        onTabRequested: (direction) => root.switchPanel(direction)
      }
    }
  }
}
