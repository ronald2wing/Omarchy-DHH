pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui

// x.com's round icon button: hover disc, hover-variant icon and a pill tooltip.
Item {
  id: button

  // Icon name under assets/icons.
  required property string icon
  required property string tooltip
  // Swaps to `<icon>-hover` while lit; false for an icon drawn without one.
  property bool hasHoverVariant: true
  property real diameter: Look.discSize
  property real iconSize: Look.actionIconSize
  property real iconOpacity: 1.0
  property color hoverColor: Look.accent
  property bool tooltipAccent: false
  // Shows the tooltip without hover, so a copy triggered from the card body
  // or the keyboard still surfaces its "Copied" confirmation.
  property bool tooltipPinned: false
  // false takes no hover or clicks of its own: for a host whose mouse area
  // spans more than the disc (an engagement count and its icon), which
  // lights the disc through `highlighted`, and for a saved image.
  property bool interactive: true
  property bool highlighted: false

  readonly property bool lit: mouse.containsMouse || button.highlighted

  signal clicked()

  width: button.diameter
  height: button.diameter

  // A pill tooltip centred below the disc; `accent` selects the accent
  // variant.
  component PillToolTip: PanelToolTip {
    id: tip

    property bool accent: false

    x: (parent.width - implicitWidth) / 2
    y: parent.height + Style.spacing.sm
    fontFamily: Look.fontFamily
    fontSize: Style.font.body
    panelForeground: tip.accent ? Look.surfaceText : Color.tooltip.text

    background: Rectangle {
      color: tip.accent ? Look.hoverFill(Look.accent) : Color.tooltip.background
      radius: 9999
    }
  }

  Rectangle {
    anchors.fill: parent
    radius: width / 2
    visible: button.lit
    color: Look.hoverFill(button.hoverColor)
  }

  Icon {
    anchors.centerIn: parent
    name: button.icon
    size: button.iconSize
    hoverVariant: button.hasHoverVariant && button.lit
    opacity: button.iconOpacity
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    enabled: button.interactive
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: button.clicked()
  }

  // Built on demand only: a Controls ToolTip is a popup, and one per disc
  // across a full result list dominated the cost of laying out results.
  Loader {
    anchors.fill: parent
    active: button.lit || button.tooltipPinned
    sourceComponent: PillToolTip {
      visible: true
      accent: button.tooltipAccent
      text: button.tooltip
    }
  }
}
