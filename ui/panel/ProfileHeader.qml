pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../base"
import "../../js/format.mjs" as Format

// The sticky x.com profile header that collapses into a compact bar as the body scrolls.
Item {
  id: header

  // The body's scroll offset under the header; drives the collapsed state.
  required property real scrollY
  required property bool following
  required property int postCount

  signal closeRequested()
  signal renderRandomRequested()
  signal searchRequested()
  signal unfollowRequested()
  signal followRequested()
  signal scrollToTopRequested()

  readonly property bool collapsed: header.scrollY >= internal.collapseThreshold

  // The 8px top margin above the fixed 46px row (2 * sm here, the row's lg
  // margin), plus 1px under it, gives x.com's compact-header height (55px
  // at scale 1).
  height: layout.height + Style.spacing.sm * 2 + Look.hairline
  z: 1

  QtObject {
    id: internal
    // scrollY below which the header counts as "at the top". The 16px margin
    // lets it revert as soon as the list is essentially at rest, without
    // waiting for the flick to decay to an exact zero.
    readonly property int collapseThreshold: Style.space(16)
  }

  // The collapsed bar's dark overlay.
  Rectangle {
    anchors.fill: parent
    color: Look.headerScrim
    opacity: header.collapsed ? 1 : 0
  }

  // Click anywhere on the bar outside its buttons to scroll to the top. The
  // buttons' own MouseAreas sit above and keep their clicks.
  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: header.scrollToTopRequested()
  }

  // Halo around the back arrow: a near-miss on Close must not scroll.
  MouseArea {
    x: layout.anchors.leftMargin - Style.spacing.sm
    y: layout.anchors.topMargin - Style.spacing.sm
    width: backButton.width + 2 * Style.spacing.sm
    height: backButton.height + 2 * Style.spacing.sm
  }

  RowLayout {
    id: layout
    anchors.top: parent.top
    anchors.topMargin: Style.spacing.lg
    anchors.left: parent.left
    anchors.leftMargin: Style.space(16)
    anchors.right: parent.right
    anchors.rightMargin: Style.space(24)
    spacing: Style.spacing.md
    // Fixed so the header height is constant whichever right-side element
    // shows; 46px clears the 20px name and the 13px post count without
    // clipping.
    height: Style.space(46)

    HeaderButton {
      id: backButton
      icon: "back"
      tooltip: "Close"
      onClicked: header.closeRequested()
    }

    // Identity block. The left margin widens the arrow→name gap to x.com's
    // ~2.8x arrow width; the row spacing alone is too tight.
    Column {
      Layout.fillWidth: true
      Layout.leftMargin: Style.space(24)
      spacing: Style.spacing.xxs

      Row {
        width: parent.width
        spacing: Style.spacing.xs

        XText {
          text: Look.dhhName
          font.pixelSize: Look.titleSize
          weight: Font.ExtraBold
          elide: Text.ElideRight
        }

        VerifiedBadge {
          size: Style.space(20)
          showAffiliate: true
          affiliateGap: Style.spacing.xs
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      XText {
        width: parent.width
        text: Format.formatPostCount(header.postCount) + " posts"
        color: Look.muted
        font.pixelSize: Look.captionSize
        elide: Text.ElideRight
      }
    }

    HeaderButton {
      icon: "grok-light"
      tooltip: "Render a random post"
      visible: !header.collapsed
      onClicked: header.renderRandomRequested()
    }

    HeaderButton {
      icon: "search"
      tooltip: "Search"
      visible: !header.collapsed
      onClicked: header.searchRequested()
    }

    // Outlined "Following" pill (red "Unfollow" on hover) or the filled
    // "Follow" button. The host owns `following`.
    PillButton {
      visible: header.collapsed
      Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
      Layout.preferredHeight: Style.space(36)
      // Inside a RowLayout the engine owns the width, so size through the
      // layout rather than a raw `width` binding. Only the longer Following
      // / Unfollow label gets x.com's 106px floor.
      Layout.preferredWidth: header.following ? Math.max(Style.space(106), implicitWidth) : implicitWidth
      label: header.following ? "Following" : "Follow"
      hoverLabel: header.following ? "Unfollow" : "Follow"
      primary: !header.following
      hoverColor: header.following ? Look.danger : "transparent"
      labelWeight: Font.DemiBold
      onClicked: {
        if (header.following) header.unfollowRequested()
        else header.followRequested()
      }
    }
  }

  // x.com's header buttons: a 34px target (larger than the shell's 28px
  // control) around a 20px icon drawn without a hover variant, with the
  // accent tooltip.
  component HeaderButton: DiscButton {
    diameter: Style.space(34)
    iconSize: Style.space(20)
    hasHoverVariant: false
    tooltipAccent: true
  }
}
