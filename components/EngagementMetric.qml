import QtQuick
import QtQuick.Layouts
import qs.Commons
import "."

// One engagement metric: an X action icon (outlined SVG, #71767B resting,
// #1D9BF0 on hover) plus an optional count, sized to the render's 18.75px
// `.action-icon` and 13px `.count`. Used four-up in the PostCard action
// row (reply/repost/like/views). Hover-only by default — its MouseArea
// accepts no buttons, so clicks still fall through to the full-surface copy
// MouseArea while hover still drives the tooltip. Setting `clickable` makes
// it accept left-clicks and emit `clicked` instead (reply opens the source,
// repost renders the shareable image). Vertically centered against the
// taller trailing bookmark/share buttons sharing the row.
//
// The root is an Item, not a Row: the hover/click MouseArea must fill the
// whole stretched slot, and a Row forbids anchors on its direct children.
// The inner Row packs the icon + count at the left of that slot, so the
// visual layout is unchanged while the hit area spans the full slot.
Item {
  id: metric

  required property string iconSource
  required property string iconSourceHover
  required property string countText
  required property string tooltip
  required property color hoverColor
  required property color barForeground
  required property color mutedColor
  required property string fontFamily
  required property real iconSize
  property bool clickable: false
  signal clicked()

  Layout.alignment: Qt.AlignVCenter

  // The root Item has no intrinsic size of its own, so mirror the inner Row's
  // implicit size: the RowLayout needs a non-zero preferred height to keep the
  // metric's vertical extent (and thus its hit area) as before.
  implicitWidth: metricRow.implicitWidth
  implicitHeight: metricRow.implicitHeight

  Row {
    id: metricRow
    spacing: Style.spacing.sm
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter

    // The disc is a child of this Item, not the Row — a Row forbids horizontal
    // anchors on direct children, so centering the disc on the icon inside a
    // plain Item keeps the Row's own horizontal layout intact (same pattern as
    // HeaderIconButton).
    Item {
      width: iconSize
      height: iconSize
      anchors.verticalCenter: parent.verticalCenter

      // Circular hover disc behind the stat icon, matching x.com's hover
      // chrome. Declared before the icon so the icon draws on top.
      Rectangle {
        width: Style.space(30)
        height: Style.space(30)
        radius: width / 2
        anchors.centerIn: parent
        visible: metricHover.containsMouse
        color: Style.hoverFillFor(barForeground, hoverColor)
      }

      // X outlined action icon, resting #71767B and turning the exact X-blue
      // #1D9BF0 on hover via a pre-rendered blue SVG variant.
      Image {
        anchors.fill: parent
        source: metricHover.containsMouse ? iconSourceHover : iconSource
        sourceSize: Qt.size(26, 26)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
      }

      // Parented to the icon host (not the Row) so CenteredToolTip's
      // `(parent.width - implicitWidth) / 2` centers on the 18.75px icon
      // instead of the wider fillWidth slot.
      CenteredToolTip {
        visible: metricHover.containsMouse
        text: tooltip
        // Qualify with `metric.`: the tooltip inherits `fontFamily`, so an
        // unqualified name would bind the tooltip's own property to itself.
        fontFamily: metric.fontFamily
        fontSize: Style.font.body
      }
    }

    Text {
      visible: countText !== ""
      anchors.verticalCenter: parent.verticalCenter
      text: countText
      textFormat: Text.PlainText
      color: metricHover.containsMouse ? hoverColor : mutedColor
      font.family: fontFamily
      font.pixelSize: Style.font.subtitle
    }
  }

  // Fills the whole stretched slot (the root Item), so hover and click cover
  // the same region the old Row-filling MouseArea intended.
  MouseArea {
    id: metricHover
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
    acceptedButtons: clickable ? Qt.LeftButton : Qt.NoButton
    onClicked: { if (clickable) metric.clicked() }
  }
}
