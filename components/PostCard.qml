import QtQuick
import QtQuick.Layouts
import qs.Commons
import "."
import "../format.js" as Fmt
import "../search.js" as Search

// One result row, shared by the search-results list and the standalone
// "History" list. Flat full-width X-style row: no card container, no
// elevation — just content separated by a 1px hairline.
//
// Interface: the per-row data/state (`entry`, `textHtml`, `cardIndex`,
// `selected`, `selectOnHover`, `showDivider`, `cardWidth`, `renderBusy`) arrives
// as explicit properties, and every action is emitted as a signal so the
// hosting panel stays the single owner of root state. The panel's read-only
// theme/resource surface (colors, fonts, sizes, icon sources — ~40 values) is
// too wide for individual props, so it rides a `required QtObject panel`
// reference to the panel root instead of many individual props.
// The card never touches `root.` — only `card` and `panel`.
Rectangle {
  id: card

  required property QtObject panel
  required property var entry
  required property string textHtml
  property int cardIndex: -1
  required property bool selected
  property bool selectOnHover: true
  property bool showDivider: true
  required property real cardWidth
  property bool renderBusy: false
  // Transient "Copied" confirmation on the copy/bookmark tooltip. Set by
  // showCopied() on every copy trigger (card body, bookmark icon, keyboard)
  // and cleared by copiedTimer; re-triggering restarts the timer.
  property bool copied: false

  readonly property var counts: Fmt.decorativeEngagementCounts(card.entry ? card.entry.text : "")
  // Reply and quote share the same visual: DHH's body above a bordered
  // context card. `quote` carries DHH's commentary in `text` and the quoted
  // post in `context`, exactly like `reply`.
  readonly property bool hasContextCard: card.entry.kind === "reply" || card.entry.kind === "quote"
  // Context author's X verified state. Absent/false hides the badge on the
  // reply/quote context row and the repost head; DHH's own badge is not gated.
  readonly property bool contextVerified: !!(card.entry.context && card.entry.context.verified === true)

  signal copyRequested()
  signal renderRequested()
  signal sourceRequested()
  signal selectedRequested(int index)
  signal dismissRequested()

  function showCopied() {
    card.copied = true
    copiedTimer.restart()
  }

  Timer {
    id: copiedTimer
    interval: 1400
    onTriggered: card.copied = false
  }

  // Context author's seal source from `context.verified_type`: organization
  // -> gold, government -> grey, individual/absent -> blue. The caller still
  // gates on `context.verified === true`; this only picks the color.
  function contextVerifiedBadgeSource(e) {
    const type = e && e.context ? e.context.verified_type : ""
    if (type === "organization") return panel.verifiedBadgeGoldSource
    if (type === "government") return panel.verifiedBadgeGreySource
    return panel.verifiedBadgeSource
  }

  // The original post's body for a repost card. A repost with `context.text`
  // (e.g. b3f7bf11) carries the quoted post there; a bare repost (e.g.
  // 1d7ae346) stores the other person's words in `text` instead. Escaped, not
  // highlight-wrapped: the original post is not the search target.
  function repostBodyHtml(e) {
    if (!e) return ""
    const body = e.context && e.context.text ? e.context.text : e.text
    return Fmt.escapeHtml(Search.stripLeadingMentions(body, Search.contextHandleOf(e)))
  }

  width: card.cardWidth
  height: cardColumn.implicitHeight + Style.spacing.md * 2
  radius: 0
  color: card.selected
    ? Style.selectedFillFor(panel.barForeground, panel.xAccent)
    : "transparent"

  // Full-surface copy MouseArea. MUST be the first child (bottom of the
  // stacking order) so the action buttons above receive their own clicks.
  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onEntered: { if (card.selectOnHover) card.selectedRequested(card.cardIndex) }
    onClicked: {
      card.showCopied()
      card.copyRequested()
      card.dismissRequested()
    }
  }

  Column {
    id: cardColumn
    anchors.fill: parent
    anchors.leftMargin: Style.space(16)
    anchors.rightMargin: Style.space(16)
    anchors.topMargin: Style.spacing.md
    anchors.bottomMargin: Style.spacing.md
    spacing: Style.spacing.sm

    // Repost header: the repost glyph + "DHH reposted" above the card, the
    // way X labels a repost in a timeline. The card below then represents the
    // original author, not DHH. X indents this header so the label lands in
    // the author-name column (avatar width + avatar→name gap); the wrapper
    // exists because a Column child cannot carry anchors.
    Item {
      width: parent.width
      height: repostHeader.height
      visible: card.entry.kind === "repost"

      Row {
        id: repostHeader
        anchors.left: parent.left
        anchors.leftMargin: panel.contentIndent - Style.space(16) - Style.spacing.xs - Style.space(4)
        spacing: Style.spacing.xs

        Image {
          width: Style.space(16)
          height: Style.space(16)
          source: panel.repostIconSource
          sourceSize: Qt.size(16, 16)
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          smooth: true
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          text: "DHH reposted"
          textFormat: Text.PlainText
          color: panel.xGray
          font.family: panel.textFontFamily
          font.pixelSize: panel.repostLabelSize
          font.bold: true
          anchors.verticalCenter: parent.verticalCenter
        }
      }
    }

    // The body sits close under the name line (X-style); the outer
    // cardColumn spacing still separates this block from the action row.
    Row {
      width: parent.width
      spacing: Style.space(12)

      Image {
        id: plainAvatar
        visible: card.entry.kind !== "repost"
        sourceSize.width: Style.space(40)
        sourceSize.height: Style.space(40)
        // Bundled local file, but a missing/corrupt asset must still fall back
        // rather than render a blank disc. Computed (not assigned) so the
        // binding survives delegate recycling.
        property bool failed: false
        source: (plainAvatar.failed || panel.avatarSource === "")
          ? panel.defaultAvatarSource
          : panel.avatarSource
        fillMode: Image.PreserveAspectFit
        onStatusChanged: {
          if (status === Image.Error) plainAvatar.failed = true
        }
      }

      // Repost: the card represents the original author, so the avatar is
      // theirs (fetched via unavatar.io) rather than DHH's bundled one.
      CircularAvatar {
        visible: card.entry.kind === "repost"
        size: Style.space(40)
        source: Search.contextAvatarUrl(Search.contextHandleOf(card.entry))
        fallbackSource: panel.defaultAvatarSource
      }

      // Content column: author line -> body -> quote. The 4px gap plus the
      // name/body text-box leading lands the name-glyph-bottom -> body-glyph-
      // top gap at ~12px logical, matching x.com.
      Column {
        width: parent.width - Style.space(40) - parent.spacing
        spacing: Style.spacing.sm

        // Author line: name/badge/logo/handle anchored left, Grok + "..."
        // cluster anchored flush right at the content column edge (x.com
        // geometry). The wrapper is clamped to the name text's line height so
        // the body follows the name (x.com starts the body just under the
        // name, not under the avatar). The 34.75px icon cluster centers on
        // this shorter row, so its glyphs stay aligned with the name line and
        // only the transparent hover disc overflows. The cluster reuses the
        // bottom action row's 34.75px circular hover-disc geometry, so the
        // "..." glyph sits flush under the share glyph below.
        Item {
          width: parent.width
          height: authorName.implicitHeight

          // Single-line author text: bold name, blue verified badge, 37signals
          // logo, muted "@dhh · <relative time>". Width is clamped short of
          // the icon cluster so long text elides rather than overlapping it.
          Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - headIconRow.width - Style.spacing.sm
            spacing: Style.spacing.xxs
            clip: true

            Text {
              id: authorName
              text: card.entry.kind === "repost" && card.entry.context && card.entry.context.author
                ? card.entry.context.author
                : panel.displayName
              textFormat: Text.PlainText
              color: panel.foreground
              font.family: panel.textFontFamily
              font.pixelSize: panel.cardTextSize
              font.bold: true
              anchors.verticalCenter: parent.verticalCenter
            }

            VerifiedBadge {
              id: authorBadge
              size: Style.space(18)
              logoSize: Style.space(14)
              showLogo: card.entry.kind !== "repost"
              badgeSource: card.entry.kind === "repost"
                ? card.contextVerifiedBadgeSource(card.entry)
                : panel.verifiedBadgeSource
              logoSource: panel.companyLogoSource
              borderColor: panel.xGray
              visible: card.entry.kind !== "repost" || card.contextVerified
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              width: Math.max(0, parent.width - authorName.implicitWidth - authorBadge.totalWidth - parent.spacing * 2)
              text: card.entry.kind === "repost"
                ? Search.contextHandleOf(card.entry) + (card.entry.context && card.entry.context.date ? " · " + Fmt.formatDate(card.entry.context.date) : "")
                : "@dhh" + (card.entry.date ? " · " + Fmt.formatDate(card.entry.date) : "")
              textFormat: Text.PlainText
              color: panel.xGray
              font.family: panel.textFontFamily
              font.pixelSize: panel.cardTextSize
              elide: Text.ElideRight
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          // x.com post-header icons (Grok AI mark + "..." more) flush right,
          // matching the render's `.head-icons` (AI first, then dots). The
          // Grok AI mark renders this entry as a shareable image; the "..."
          // opens the entry's source link. Same 34.75px circular hover-disc
          // geometry as the bottom action row's bookmark/share buttons.
          Row {
            id: headIconRow
            spacing: panel.discOverlap
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            HoverDiscButton {
              icon: panel.grokIconSource
              iconHover: panel.grokIconSourceHover
              iconSourceSize: panel.grokIconSize
              tooltip: panel.renderIconTooltip
              iconSize: panel.xActionIconSize
              barForeground: panel.barForeground
              accentColor: panel.xAccent
              fontFamily: panel.textFontFamily
              onClicked: {
                card.renderRequested()
                card.dismissRequested()
              }
            }

            HoverDiscButton {
              icon: panel.dotsIconSource
              iconHover: panel.dotsIconSourceHover
              iconSourceSize: Qt.size(40, 40)
              tooltip: "Open source"
              iconSize: panel.xActionIconSize
              barForeground: panel.barForeground
              accentColor: panel.xAccent
              fontFamily: panel.textFontFamily
              onClicked: {
                card.sourceRequested()
                card.dismissRequested()
              }
            }
          }
        }

        // Plain body: a post with no reply/repost/quote kind renders DHH's
        // words directly (standalone `type: "quote"` entries render like
        // posts, with no bordered box; `kind: "quote"` uses the context card
        // below instead).
        PostBodyText {
          visible: !card.hasContextCard && card.entry.kind !== "repost"
          text: card.textHtml
          color: panel.foreground
          fontFamily: panel.textFontFamily
          pixelSize: panel.cardTextSize
          lineHeight: panel.cardLineHeight
        }

        // Repost: the card is the original post, so the body is the original
        // author's words (context.text, or `text` for a bare repost) with no
        // bordered quote box — the header above already names the author.
        PostBodyText {
          visible: card.entry.kind === "repost"
          text: card.repostBodyHtml(card.entry)
          color: panel.foreground
          fontFamily: panel.textFontFamily
          pixelSize: panel.cardTextSize
          lineHeight: panel.cardLineHeight
        }

        // Reply/quote: DHH's body followed by the original post as a bordered
        // quoted card (author + handle + body), matching x.com's quote-post
        // style with no "replying to" line. For a reply the body is DHH's
        // reply and the card is the post answered; for a quote the body is
        // DHH's commentary and the card is the post quoted. The original post
        // lives in context and is not the search target, so its body is
        // escaped, not highlight-wrapped.
        Column {
          visible: card.hasContextCard
          width: parent.width
          spacing: Style.spacing.md

          PostBodyText {
            text: card.textHtml
            color: panel.foreground
            fontFamily: panel.textFontFamily
            pixelSize: panel.cardTextSize
            lineHeight: panel.cardLineHeight
          }

          Rectangle {
            width: parent.width
            height: replyQuoteColumn.implicitHeight + Style.space(12) * 2
            radius: 16
            border.width: 1
            border.color: panel.xDivider
            color: "transparent"

            Column {
              id: replyQuoteColumn
              width: parent.width - Style.space(12) * 2
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.xxs

              Row {
                width: parent.width
                spacing: Style.spacing.xs
                CircularAvatar {
                  size: Style.space(20)
                  source: Search.contextAvatarUrl(card.entry.context && card.entry.context.handle)
                  fallbackSource: panel.defaultAvatarSource
                  anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                  id: quoteAuthorName
                  text: card.entry.context && card.entry.context.author ? card.entry.context.author : ""
                  textFormat: Text.PlainText
                  color: panel.foreground
                  font.family: panel.textFontFamily
                  font.pixelSize: panel.cardTextSize
                  font.bold: true
                  anchors.verticalCenter: parent.verticalCenter
                }
                VerifiedBadge {
                  id: quoteAuthorBadge
                  size: Style.space(14)
                  showLogo: false
                  badgeSource: card.contextVerifiedBadgeSource(card.entry)
                  logoSource: panel.companyLogoSource
                  borderColor: panel.xGray
                  visible: card.contextVerified
                  anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                  width: parent.width - Style.space(20) - Style.spacing.xs * 2 - quoteAuthorName.width - quoteAuthorBadge.totalWidth
                  text: card.entry.context && card.entry.context.handle ? card.entry.context.handle + (card.entry.context.date ? " · " + Fmt.formatDate(card.entry.context.date) : "") : ""
                  textFormat: Text.PlainText
                  color: panel.xGray
                  font.family: panel.textFontFamily
                  font.pixelSize: panel.cardTextSize
                  elide: Text.ElideRight
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              Text {
                width: parent.width
                text: card.entry.context && card.entry.context.text ? Fmt.escapeHtml(card.entry.context.text) : ""
                textFormat: Text.RichText
                color: panel.foreground
                font.family: panel.textFontFamily
                font.pixelSize: panel.cardTextSize
                lineHeightMode: Text.FixedHeight
                lineHeight: panel.cardLineHeight
                wrapMode: Text.WordWrap
              }
            }
          }
        }

      }
    }
    // Bottom action area: a single row matching the render's `.action-row`.
    // The four engagement metrics (reply/repost/like/views) share the row
    // width equally so their icons land at evenly-spaced positions; a fixed
    // gap then holds the functional bookmark + share buttons as a flush-right
    // trailing cluster, in the position real X gives its bookmark/share.
    RowLayout {
      anchors.left: parent.left
      anchors.leftMargin: panel.contentIndent
      anchors.right: parent.right
      spacing: 0

      EngagementMetric {
        iconSource: panel.replyIconSource
        iconSourceHover: panel.replyIconSourceHover
        countText: Fmt.formatEngagementCount(card.counts.reply)
        tooltip: "Reply"
        hoverColor: panel.xAccent
        barForeground: panel.barForeground
        mutedColor: panel.xGray
        fontFamily: panel.textFontFamily
        iconSize: panel.xActionIconSize
        Layout.fillWidth: true
        Layout.preferredWidth: 0
        clickable: true
        onClicked: {
          card.sourceRequested()
          card.dismissRequested()
        }
      }
      EngagementMetric {
        iconSource: panel.repostIconSource
        iconSourceHover: panel.repostIconSourceHover
        countText: Fmt.formatEngagementCount(card.counts.repost)
        tooltip: "Repost"
        hoverColor: panel.xRepostGreen
        barForeground: panel.barForeground
        mutedColor: panel.xGray
        fontFamily: panel.textFontFamily
        iconSize: panel.xActionIconSize
        Layout.fillWidth: true
        Layout.preferredWidth: 0
        clickable: true
        onClicked: {
          card.renderRequested()
          card.dismissRequested()
        }
      }
      EngagementMetric {
        iconSource: panel.likeIconSource
        iconSourceHover: panel.likeIconSourceHover
        countText: Fmt.formatEngagementCount(card.counts.like)
        tooltip: "Like"
        hoverColor: panel.xLikePink
        barForeground: panel.barForeground
        mutedColor: panel.xGray
        fontFamily: panel.textFontFamily
        iconSize: panel.xActionIconSize
        Layout.fillWidth: true
        Layout.preferredWidth: 0
      }
      EngagementMetric {
        iconSource: panel.viewsIconSource
        iconSourceHover: panel.viewsIconSourceHover
        countText: Fmt.formatEngagementCount(card.counts.views)
        tooltip: "Views"
        hoverColor: panel.xAccent
        barForeground: panel.barForeground
        mutedColor: panel.xGray
        fontFamily: panel.textFontFamily
        iconSize: panel.xActionIconSize
        Layout.fillWidth: true
        Layout.preferredWidth: 0
      }

      Row {
        spacing: panel.discOverlap

        // Flat trailing action icons (X-style bookmark/share): 18.75px muted
        // gray, turning X-blue on hover, each on a 34.75px circular
        // hover-disc hit target (HoverDiscButton).
        HoverDiscButton {
          icon: panel.bookmarkIconSource
          iconHover: panel.bookmarkIconSourceHover
          iconSourceSize: Qt.size(24, 24)
          tooltip: card.copied ? "Copied" : "Copy to clipboard"
          tooltipForced: card.copied
          iconSize: panel.xActionIconSize
          barForeground: panel.barForeground
          accentColor: panel.xAccent
          fontFamily: panel.textFontFamily
          onClicked: {
            card.showCopied()
            card.copyRequested()
            card.dismissRequested()
          }
        }

        HoverDiscButton {
          icon: panel.shareIconSource
          iconHover: panel.shareIconSourceHover
          iconSourceSize: Qt.size(24, 24)
          tooltip: panel.renderIconTooltip
          iconSize: panel.xActionIconSize
          barForeground: panel.barForeground
          accentColor: panel.xAccent
          fontFamily: panel.textFontFamily
          iconOpacity: card.renderBusy ? panel.renderingIconOpacity : 1.0
          onClicked: {
            card.renderRequested()
            card.dismissRequested()
          }
        }
      }
    }
  }

  // 1px hairline divider between rows (X-style). Solid #2F3336, X's exact
  // divider gray — an alpha-blended foreground was invisible against the
  // themed panel background, so the divider stays a fixed solid gray.
  Rectangle {
    visible: card.showDivider
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: 1
    color: panel.xDivider
  }
}
