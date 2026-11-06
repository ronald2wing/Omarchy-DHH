pragma ComponentBehavior: Bound
import QtQuick
import "../base"
import "../../js/entries.mjs" as Entries
import "../../js/format.mjs" as Format

// x.com's timeline post, drawn once for the panel's cards and the saved image: repost header, author line, body, context card and action row.
Item {
  id: post

  // x.com's CSS-pixel geometry from Look, never scaled with the shell's
  // spacing, so the post is x.com's on every machine and on both surfaces.

  required property var entry
  // The entry's own body (Entries.postBody), HTML-escaped; the panel passes
  // it with search highlights. A repost shows the reposted post's body
  // instead, escaped, not highlighted: the original post is not the search
  // target.
  property string bodyHtml: Format.escapeHtml(Entries.postBody(post.entry))
  // The context author's avatar data URI ("" shows the fallback avatar).
  required property string contextAvatarSource
  // false draws the saved image: no hover, no clicks, and the head marks as
  // plain icons.
  property bool interactive: true
  // The colour of names and bodies; handles, counts and the repost label
  // are always Look.muted.
  property color textColor: Look.themeText
  property bool curveRendered: false
  property real avatarPixelRatio: Screen.devicePixelRatio
  // The bookmark's tooltip reads "Copied", pinned, while true.
  property bool copied: false
  // This post's entry is rendering: its share icon dims.
  property bool rendering: false

  signal copyRequested()
  signal renderRequested()
  signal openSourceRequested()

  implicitHeight: Look.postTopPadding + column.implicitHeight + Look.postBottomPadding

  QtObject {
    id: internal

    readonly property bool isRepost: Entries.isRepost(post.entry)
    // The other post's author line: the context card's, and for a repost
    // the post's own, since that post is theirs. Their badge shows only when
    // they are actually verified; DHH's own badge is unconditional. Data the
    // dataset validator rejects still draws one way on both surfaces: a
    // repost without an author shows an empty name (not DHH's beside someone
    // else's handle), and a context without a handle keeps its avatar slot
    // with the fallback avatar, as x.com draws it.
    readonly property var context: post.entry.context || ({})
    readonly property string contextAuthor: String(internal.context.author || "")
    readonly property string contextHandle: Entries.contextHandle(post.entry)
    readonly property string contextDate: String(internal.context.date || "")
    readonly property bool contextVerified: internal.context.verified === true
    readonly property string contextVerifiedType: String(internal.context.verified_type || "")

    // The action row, as on x.com. The counts are decorative and keyed by
    // the icon name. Two engagements act as shortcuts: Reply opens the
    // source (where a reply would be written) and Repost renders the image.
    readonly property var counts: Format.decorativeEngagementCounts(post.entry.text)
    readonly property var engagements: [
      { icon: "reply", tooltip: "Reply", hoverColor: Look.accent, activate: () => post.openSourceRequested() },
      { icon: "repost", tooltip: "Repost", hoverColor: Look.repostGreen, activate: () => post.renderRequested() },
      { icon: "like", tooltip: "Like", hoverColor: Look.likePink, activate: null },
      { icon: "views", tooltip: "Views", hoverColor: Look.accent, activate: null }
    ]
  }

  // "DHH reposted", indented so the label lands in the author-name column.
  component RepostHeader: Item {
    width: parent.width
    height: header.height + Look.repostHeaderGap

    Row {
      id: header
      x: Look.repostHeaderIndent
      spacing: Look.repostIconGap

      Icon {
        name: "repost"
        size: Look.repostIconSize
        anchors.verticalCenter: parent.verticalCenter
      }

      XText {
        text: Look.dhhName + " reposted"
        color: Look.muted
        font.pixelSize: Look.captionSize
        weight: Font.Bold
        curveRendered: post.curveRendered
        anchors.verticalCenter: parent.verticalCenter
      }
    }
  }

  // The post a reply answers or a quote quotes, in a bordered card under
  // the body: avatar, author line, body.
  component ContextCard: Item {
    width: parent.width
    height: Look.contextCardGap + frame.height

    Rectangle {
      id: frame
      y: Look.contextCardGap
      width: parent.width
      height: contextColumn.implicitHeight + (Look.contextCardPadding + Look.hairline) * 2
      radius: Look.contextCardRadius
      border.width: Look.hairline
      border.color: Look.divider
      color: "transparent"

      Column {
        id: contextColumn
        x: Look.contextCardPadding + Look.hairline
        y: x
        width: parent.width - x * 2

        AuthorLine {
          width: parent.width
          height: Look.contextAvatarSize
          avatarSize: Look.contextAvatarSize
          avatarSource: post.contextAvatarSource
          avatarPixelRatio: post.avatarPixelRatio
          name: internal.contextAuthor
          handle: internal.contextHandle
          date: internal.contextDate
          verified: internal.contextVerified
          verifiedType: internal.contextVerifiedType
          textColor: post.textColor
          curveRendered: post.curveRendered
        }

        // Explicit, not Column spacing: Column skips an empty body, and CSS
        // keeps the margin.
        Item { width: 1; height: Look.contextBodyGap }

        PostBody {
          width: parent.width
          html: Format.escapeHtml(String(internal.context.text || ""))
          color: post.textColor
          curveRendered: post.curveRendered
        }
      }
    }
  }

  // The head marks: the Grok mark renders the entry as an image, the "..."
  // opens its source. The panel draws them as hover discs, the image as
  // plain icons. The disc centres the Grok mark on a whole pixel and draws
  // it square, so it sits 0.71px left of, 1px above and taller than the
  // image's 19.33 x 18.75 mark; the clusters stay separate so neither moves.
  Component {
    id: headDiscs

    Row {
      spacing: Look.headDiscSpacing

      DiscButton {
        icon: "grok"
        iconSize: Look.grokWidth
        tooltip: "Render image"
        onClicked: post.renderRequested()
      }

      DiscButton {
        icon: "dots"
        tooltip: "Open source"
        onClicked: post.openSourceRequested()
      }
    }
  }

  Component {
    id: headIcons

    Row {
      height: Look.authorLineHeight
      spacing: Look.headIconGap

      // The Grok mark's viewBox is 33x32.
      Icon {
        name: "grok"
        size: Look.grokWidth
        height: Look.headIconSize
        anchors.verticalCenter: parent.verticalCenter
      }

      Icon {
        name: "dots"
        size: Look.headIconSize
        anchors.verticalCenter: parent.verticalCenter
      }
    }
  }

  Column {
    id: column
    x: Look.postSidePadding
    y: Look.postTopPadding
    width: parent.width - Look.postSidePadding * 2

    RepostHeader {
      visible: internal.isRepost
    }

    Row {
      width: parent.width
      spacing: Look.avatarGap

      // DHH's own avatar (bundled, pre-cropped), or the original author's for
      // a repost, since that post is theirs.
      Avatar {
        size: Look.avatarSize
        pixelRatio: post.avatarPixelRatio
        source: internal.isRepost ? post.contextAvatarSource : Look.dhhAvatar
        masked: internal.isRepost
      }

      Column {
        width: parent.width - Look.contentIndent

        // The author line, and the head marks flush right on its 20px line.
        Item {
          width: parent.width
          height: Look.authorLineHeight

          AuthorLine {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - (Look.grokWidth + Look.headIconGap + Look.headIconSize) - Look.headIconGap
            clip: true
            name: internal.isRepost ? internal.contextAuthor : Look.dhhName
            handle: internal.isRepost ? internal.contextHandle : Look.dhhHandle
            date: internal.isRepost ? internal.contextDate : String(post.entry.date || "")
            verified: !internal.isRepost || internal.contextVerified
            verifiedType: internal.isRepost ? internal.contextVerifiedType : ""
            showAffiliate: !internal.isRepost
            textColor: post.textColor
            curveRendered: post.curveRendered
          }

          // The marks sit where x.com's do (the "..." flush with the text
          // column's end); the panel's hover discs spill past them.
          Loader {
            anchors.right: parent.right
            anchors.rightMargin: post.interactive ? -(Look.discSize - Look.headIconSize) / 2 : 0
            anchors.verticalCenter: parent.verticalCenter
            sourceComponent: post.interactive ? headDiscs : headIcons
          }
        }

        Item { width: 1; height: Look.bodyGap }

        PostBody {
          width: parent.width
          html: internal.isRepost ? Format.escapeHtml(Entries.repostedBody(post.entry)) : post.bodyHtml
          color: post.textColor
          curveRendered: post.curveRendered
        }

        ContextCard {
          visible: Entries.hasContextCard(post.entry)
        }
      }
    }

    Item { width: 1; height: Look.actionRowGap }

    // Four engagements sharing what the bookmark and share icons leave, then
    // those icons flush right.
    Item {
      id: actionRow
      x: Look.contentIndent
      width: parent.width - Look.contentIndent
      height: Look.actionRowHeight

      readonly property real engagementWidth: (actionRow.width - Look.actionIconSize * 2 - Look.trailIconGap - Look.engagementGap * 4) / 4

      Row {
        height: parent.height
        spacing: Look.engagementGap

        Repeater {
          model: internal.engagements

          delegate: EngagementCount {
            id: engagement
            required property var modelData

            width: actionRow.engagementWidth
            height: actionRow.height
            icon: engagement.modelData.icon
            count: internal.counts[engagement.modelData.icon]
            tooltip: engagement.modelData.tooltip
            hoverColor: engagement.modelData.hoverColor
            clickable: !!engagement.modelData.activate
            interactive: post.interactive
            curveRendered: post.curveRendered
            onClicked: engagement.modelData.activate()
          }
        }
      }

      // The icons sit where x.com's do (the share icon flush with the text
      // column's end); the panel's hover discs spill past them.
      Row {
        x: (actionRow.engagementWidth + Look.engagementGap) * 4 - (Look.discSize - Look.actionIconSize) / 2
        anchors.verticalCenter: parent.verticalCenter
        spacing: Look.trailDiscSpacing

        DiscButton {
          icon: "bookmark"
          tooltip: post.copied ? "Copied" : "Copy to clipboard"
          tooltipPinned: post.copied
          interactive: post.interactive
          onClicked: post.copyRequested()
        }

        DiscButton {
          icon: "share"
          tooltip: "Render image"
          iconOpacity: post.rendering ? Look.renderingIconOpacity : 1.0
          interactive: post.interactive
          onClicked: post.renderRequested()
        }
      }
    }
  }
}
