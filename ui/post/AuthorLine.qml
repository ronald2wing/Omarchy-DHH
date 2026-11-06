pragma ComponentBehavior: Bound
import QtQuick
import "../base"
import "../../js/format.mjs" as Format

// A post's author line as x.com spaces it: avatar, name, verified badge, then "@handle · date".
Row {
  id: line

  required property string name
  required property string handle
  property string date: ""
  required property bool verified
  property string verifiedType: ""
  property bool showAffiliate: false
  // Diameter of the leading avatar, set Look.contextAvatarGap before the
  // name; 0 leaves it out.
  property int avatarSize: 0
  // "" shows the fallback avatar.
  property string avatarSource: ""
  property real avatarPixelRatio: Screen.devicePixelRatio
  // The name's colour; the handle and date are always Look.muted.
  property color textColor: Look.themeText
  property bool curveRendered: false

  // A Loader, so a line without an avatar builds no mask layer.
  Loader {
    active: line.avatarSize > 0
    anchors.verticalCenter: parent.verticalCenter
    // The gap is part of the loaded item: a Loader given a width resizes
    // what it loads.
    sourceComponent: Item {
      width: line.avatarSize + Look.contextAvatarGap
      height: line.avatarSize

      Avatar {
        size: line.avatarSize
        source: line.avatarSource
        pixelRatio: line.avatarPixelRatio
      }
    }
  }

  XText {
    text: line.name
    weight: Font.Bold
    color: line.textColor
    curveRendered: line.curveRendered
    anchors.verticalCenter: parent.verticalCenter
  }

  VerifiedBadge {
    visible: line.verified
    size: Look.sealSize
    leadingGap: Look.sealGap
    affiliateGap: Look.affiliateGap
    affiliateSize: Look.affiliateSize
    trailingGap: Look.affiliateTrailing
    showAffiliate: line.showAffiliate
    verifiedType: line.verifiedType
    anchors.verticalCenter: parent.verticalCenter
  }

  // Last in the Row, so its x is where the items before it end. The caller
  // sets the line's width; this text takes what is left.
  XText {
    id: handleText
    width: Math.max(0, line.width - handleText.x)
    leftPadding: Look.handleGap
    text: Format.handleLine(line.handle, line.date)
    color: Look.muted
    elide: Text.ElideRight
    curveRendered: line.curveRendered
    anchors.verticalCenter: parent.verticalCenter
  }
}
