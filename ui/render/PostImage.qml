pragma ComponentBehavior: Bound
import QtQuick
import "../base"
import "../post"

// The X post the renderer saves as an image: x.com's timeline post in its 598px column, on x.com's black.
Rectangle {
  id: image

  required property var entry
  // The context author's avatar data URI ("" shows the fallback avatar).
  property string contextAvatarSource: ""

  width: Look.columnWidth
  height: post.implicitHeight
  color: Look.surface

  // The panel's post, drawn still: x.com's fixed light grey instead of the
  // theme's text colour, curve-rendered text and avatars rasterised for the
  // renderer's Look.imageScale grab.
  TimelinePost {
    id: post
    width: parent.width
    entry: image.entry
    contextAvatarSource: image.contextAvatarSource
    interactive: false
    textColor: Look.surfaceText
    curveRendered: true
    avatarPixelRatio: Look.imageScale
  }
}
