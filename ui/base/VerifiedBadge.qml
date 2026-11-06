pragma ComponentBehavior: Bound
import QtQuick
import "../../js/format.mjs" as Format

// x.com's verified seal for a verification type, optionally followed by the affiliate logo.
Item {
  id: badge

  property string verifiedType: ""
  required property real size
  property bool showAffiliate: false
  property real affiliateSize: badge.size
  // Space before the seal, between the seal and the logo, and after the
  // logo, all inside the badge's `width` (which callers read).
  property real leadingGap: 0
  property real affiliateGap: 0
  property real trailingGap: 0

  width: badge.leadingGap + badge.size + (badge.showAffiliate ? badge.affiliateGap + badge.affiliateSize + badge.trailingGap : 0)
  height: Math.max(badge.size, badge.affiliateSize)

  Icon {
    id: seal
    x: badge.leadingGap
    anchors.verticalCenter: parent.verticalCenter
    name: Format.sealIconName(badge.verifiedType)
    size: badge.size
  }

  Rectangle {
    visible: badge.showAffiliate
    width: badge.affiliateSize
    height: badge.affiliateSize
    anchors.left: seal.right
    anchors.leftMargin: badge.affiliateGap
    anchors.verticalCenter: parent.verticalCenter
    color: "transparent"
    border.width: Look.hairline
    border.color: Look.muted

    Image {
      anchors.fill: parent
      source: Look.affiliateLogo
      sourceSize: Qt.size(32, 32)
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      smooth: true
    }
  }
}
