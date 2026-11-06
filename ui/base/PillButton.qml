pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons

// x.com's pill button (Following/Unfollow, the dialog buttons).
Rectangle {
  id: pill

  required property string label
  // `hoverLabel` and `hoverColor` restyle the pill on hover: "Following"
  // turns into a red "Unfollow".
  property string hoverLabel: pill.label
  property bool primary: false
  // Transparent (the default) keeps the secondary's border and label colours
  // on hover and overlays the button fill.
  property color hoverColor: "transparent"
  property int labelWeight: Font.Bold

  signal clicked()

  implicitWidth: caption.implicitWidth + Style.space(32)
  implicitHeight: Style.space(44)
  radius: height / 2
  color: pill.primary
    ? (internal.hovered ? Look.buttonFillHover : Look.buttonFill)
    : (internal.hovered ? Util.alpha(internal.tinted ? pill.hoverColor : Look.buttonFill, 0.1) : "transparent")
  border.width: pill.primary ? 0 : Look.hairline
  border.color: internal.tinted ? pill.hoverColor : Look.mutedBorder

  QtObject {
    id: internal
    readonly property bool hovered: mouse.containsMouse
    // A hover colour is set and showing: it tints the border, fill and label.
    readonly property bool tinted: internal.hovered && pill.hoverColor.a > 0
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: pill.clicked()
  }

  XText {
    id: caption
    anchors.centerIn: parent
    text: internal.hovered ? pill.hoverLabel : pill.label
    color: pill.primary ? Look.buttonText : (internal.tinted ? pill.hoverColor : Look.surfaceText)
    weight: pill.labelWeight
  }
}
