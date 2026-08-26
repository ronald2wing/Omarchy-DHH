pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as QQC
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "search.js" as Search
import "format.js" as Fmt

Panel {
  id: root
  moduleName: "dhh"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var service: null

  property string query: ""
  property string statusText: ""
  property string toast: ""
  property string lastRenderPath: ""
  property string renderingText: ""
  property string renderStderr: ""
  property bool renderTimedOut: false
  property int selectedIndex: 0
  property var suggestions: []
  property bool workerReady: false
  property var highlightCache: Object.create(null)

  readonly property int maxResults: 40
  readonly property string renderScriptPath: Search.fileUrlToPath(Qt.resolvedUrl("bin/omarchy-dhh-render"))

  readonly property var barOwner: hostWidget || root
  // Proportional sans for all readable text, matching real X's Chirp. All
  // icons are SVGs.
  readonly property string textFontFamily: "Noto Sans"
  readonly property color foreground: Color.foreground
  readonly property real opacitySecondary: 0.62
  readonly property var sourceSchemeRe: /^https?:\/\//
  // Opacity the share icon drops to while its entry's render is in flight.
  readonly property real dimmedOpacity: 0.4

  // X-brand accent pushed through the theme-aware chrome.
  readonly property color xAccent: "#1D9BF0"

  // X dark-mode palette + action-icon size, kept in sync with the render
  // script's inline CSS (bin/omarchy-dhh-render): .handle/.count fill #71767B,
  // .quote-container border #2F3336, .post-body/.name text #E7E9EA.
  // Resting search ring matches X's muted #536471 (panel-only).
  // .action-icon is 18.75px square.
  readonly property string xGray: "#71767B"
  readonly property string xDivider: "#2F3336"
  readonly property string xText: "#E7E9EA"
  readonly property string xMuted: "#536471"
  readonly property real xActionIconSize: Style.spaceReal(18.75)

  readonly property string avatarSource: Qt.resolvedUrl("data/avatar-x.png")
  readonly property string defaultAvatarSource: Qt.resolvedUrl("data/avatar-default.png")
  readonly property string companyLogoSource: Qt.resolvedUrl("data/company-logo.png")
  readonly property string renderImageTooltip: "Render image"
  readonly property string grokIconSource: Qt.resolvedUrl("data/icon-grok.svg")
  readonly property string grokIconSourceHover: Qt.resolvedUrl("data/icon-grok-blue.svg")
  readonly property string dotsIconSource: Qt.resolvedUrl("data/icon-dots.svg")
  readonly property string dotsIconSourceHover: Qt.resolvedUrl("data/icon-dots-blue.svg")

  // X chrome icons (verified badge, back/grok/search): single-path SVGs with
  // solid X colors baked in (e.g. #1D9BF0 verified seal).
  readonly property string verifiedBadgeSource: Qt.resolvedUrl("data/icon-verified.svg")
  readonly property string backIconSource: Qt.resolvedUrl("data/icon-back.svg")
  readonly property string grokIconSourceLight: Qt.resolvedUrl("data/icon-grok-light.svg")
  readonly property string searchIconSource: Qt.resolvedUrl("data/icon-search.svg")

  // Stat action icons (reply/repost/like/views): X's outlined shapes as SVGs,
  // resting gray (#71767B) and pre-rendered X-blue (#1D9BF0) on hover.
  // The blue variants are baked in so the hover color matches root.xAccent
  // exactly without colorizing at draw time.
  readonly property string replyIconSource: Qt.resolvedUrl("data/icon-reply.svg")
  readonly property string repostIconSource: Qt.resolvedUrl("data/icon-repost.svg")
  readonly property string likeIconSource: Qt.resolvedUrl("data/icon-like.svg")
  readonly property string viewsIconSource: Qt.resolvedUrl("data/icon-views.svg")
  readonly property string replyIconSourceHover: Qt.resolvedUrl("data/icon-reply-blue.svg")
  readonly property string repostIconSourceHover: Qt.resolvedUrl("data/icon-repost-blue.svg")
  readonly property string likeIconSourceHover: Qt.resolvedUrl("data/icon-like-blue.svg")
  readonly property string viewsIconSourceHover: Qt.resolvedUrl("data/icon-views-blue.svg")

  // Trailing action icons (bookmark/share) and the open-folder button: filled
  // shapes as SVGs, resting #71767B and pre-rendered X-blue
  // (#1D9BF0) on hover. The folder follows the same gray->blue hover swap;
  // the search clear "×" is a flat-black mark on a white disc, and the
  // recent-dropdown remove "×" is a flat X-blue mark.
  readonly property string bookmarkIconSource: Qt.resolvedUrl("data/icon-bookmark.svg")
  readonly property string bookmarkIconSourceHover: Qt.resolvedUrl("data/icon-bookmark-blue.svg")
  readonly property string shareIconSource: Qt.resolvedUrl("data/icon-share.svg")
  readonly property string shareIconSourceHover: Qt.resolvedUrl("data/icon-share-blue.svg")
  readonly property string folderIconSource: Qt.resolvedUrl("data/icon-folder.svg")
  readonly property string folderIconSourceHover: Qt.resolvedUrl("data/icon-folder-blue.svg")
  readonly property string clearSearchIconSource: Qt.resolvedUrl("data/icon-xmark.svg")
  readonly property string removeRecentIconSource: Qt.resolvedUrl("data/icon-xmark-blue.svg")

  // Body/action-row left indent: circular avatar (40) + gutter (12) = 52px,
  // matching the render's `.post-body`/`.action-row` `margin-left: 52px`.
  readonly property int contentIndent: Style.space(40) + Style.space(12)

  // contentY below which the header counts as "at the top" and shows its
  // expanded/icon state. A small epsilon (instead of an exact `=== 0`) lets
  // the header revert the moment the list is essentially at the top, without
  // waiting for the Flickable's momentum to decay to an exact zero offset.
  readonly property int headerRevertThreshold: Style.space(16)

  // Total scrollable content height: the sticky header plus the body column
  // plus the top/bottom gutter. Shared by the keyboard panel's fitted height
  // and the body Flickable's contentHeight so they can't drift apart.
  readonly property real contentTotalHeight: headerBar.height + bodyColumn.implicitHeight + Style.spacing.lg * 2

  readonly property string sectionTitle: "DHH"

  function open() {
    if (root.service) root.service.onOpened()
    controller.show()
  }

  function close() { controller.hide() }

  function toggle() {
    if (root.opened) { root.close(); return }
    root.open()
  }

  Component.onCompleted: {
    root.ensureWorkerInit()
  }

  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function") return bar.switchPanelFrom(barOwner, direction)
    return false
  }

  function escapeRegex(s) {
    return String(s).replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
  }

  function highlightQuery(text, query) {
    const t = String(text || "")
    const q = String(query || "").trim()
    if (q === "") return Fmt.escapeHtml(t)
    const key = q.toLowerCase()
    let re = root.highlightCache[key]
    if (re === undefined) {
      const words = key.split(/\s+/).filter(w => w !== "")
      if (words.length === 0) return Fmt.escapeHtml(t)
      re = new RegExp("(" + words.map(escapeRegex).join("|") + ")", "gi")
      root.highlightCache[key] = re
    }
    return Fmt.escapeHtml(t).replace(re, "<b>$1</b>")
  }

  function scheduleSearch() {
    root.selectedIndex = 0
    searchTimer.restart()
    recordTimer.restart()
  }

  // Reorder a suggestion list so trending terms lead (in trending order),
  // followed by the remaining terms in their original worker order.
  function orderSuggestions(list) {
    const terms = root.service && root.service.trendingTerms ? root.service.trendingTerms : []
    if (terms.length === 0 || !list) return list || []
    const trending = terms.filter(t => list.includes(t))
    return trending.concat(list.filter(w => !trending.includes(w)))
  }

  function runSearch() {
    resultModel.clear()
    root.highlightCache = Object.create(null)
    root.suggestions = []
    if (root.query.trim() === "") { root.statusText = ""; return }
    // Connections may miss entriesLoadedChanged if service loads before
    // Panel receives the injection; retry the init handshake here so the
    // user never sees a perpetual "Loading dataset…".
    if (!root.workerReady) root.ensureWorkerInit()
    if (!root.workerReady) {
      root.statusText = "Loading dataset…"
      return
    }
    root.statusText = "Searching…"
    searchWorker.sendMessage({ type: "search", query: root.query, maxResults: root.maxResults })
  }

  function ensureWorkerInit() {
    if (!root.workerReady && root.service && root.service.entriesLoaded) {
      searchWorker.sendMessage({ type: "init", entries: root.service.entries })
    }
  }

  function setResultStatus(count) {
    if (count > 0) root.statusText = count + " result" + (count === 1 ? "" : "s")
    else root.statusText = "No matches for: " + root.query
  }

  function moveSelection(delta) {
    if (resultModel.count === 0) return
    root.selectedIndex = Math.max(0, Math.min(resultModel.count - 1, root.selectedIndex + delta))
    // The results list now sizes to its full content and no longer scrolls
    // internally, so keep the selected row visible by scrolling the outer
    // bodyScroll Flickable instead of the inner ListView. The header overlays
    // the top of bodyScroll, so rows must stay clear of it (below
    // headerBar.height), not merely within the viewport.
    const row = resultScroll.itemAtIndex(root.selectedIndex)
    if (row) {
      const yInView = row.mapToItem(bodyScroll, 0, 0).y
      if (yInView < headerBar.height) {
        bodyScroll.contentY += yInView - headerBar.height
      } else if (yInView + row.height > bodyScroll.height) {
        bodyScroll.contentY += yInView + row.height - bodyScroll.height
      }
    }
  }

  function copyToClipboard(text) {
    Quickshell.execDetached(["bash", "-c", "printf %s " + Util.shellQuote(text) + " | wl-copy"])
  }

  function copyEntry(entry) {
    const attribution = "— David Heinemeier Hansson (@dhh)"
    const url = entry.source || ""
    const parts = []

    if (entry.type === "link") {
      const head = []
      if (entry.title) head.push(entry.title)
      if (entry.domain) head.push(entry.domain)
      if (url) head.push(url)
      parts.push(head.join("\n"))
      // The commentary is separated from the head block by a blank line, so
      // the text part carries one newline and the final "\n" join adds the
      // second.
      if (entry.text) parts.push("\n" + entry.text)
    } else {
      parts.push((entry.text || "") + "\n\n" + attribution)
      if (url) parts.push(url)
    }

    root.copyToClipboard(parts.join("\n"))
    root.showToast("Copied")
    if (root.service) root.service.recordHistoryEntry(entry)
  }

  function entryAt(index) {
    if (index < 0 || index >= resultModel.count) return null
    const row = resultModel.get(index)
    return Search.pickEntry(row)
  }

  // Resolve a reply/repost context author's avatar via unavatar.io (dynamic,
  // fetched online at runtime). Strips the leading '@' — the resolver expects
  // the bare handle. Returns "" for a missing handle (no avatar rendered).
  function contextAvatarUrlFor(handle) {
    return handle ? "https://unavatar.io/x/" + handle.replace(/^@/, "") : ""
  }

  function copyEntryAt(index) {
    const entry = root.entryAt(index)
    if (entry) root.copyEntry(entry)
  }

  function renderEntry(entry) {
    // One render at a time: ignore clicks while a render is in flight.
    if (root.service && root.service.generating) return
    if (root.service) {
      root.service.generating = true
      root.service.renderPathDelivered = false
      root.service.recordHistoryEntry(entry)
    }
    root.renderingText = entry.text
    root.renderStderr = ""
    root.renderTimedOut = false
    renderProcess.exec([root.renderScriptPath, JSON.stringify(entry)])
    renderWatchdog.restart()
  }

  function renderEntryAt(index) {
    const entry = root.entryAt(index)
    if (entry) root.renderEntry(entry)
  }

  // Render a random entry as a shareable image (records history like any other
  // render). Guarded against an unloaded or empty dataset.
  function renderRandomEntry() {
    if (!root.service || !root.service.entriesLoaded || root.service.entries.length === 0) {
      root.showToast("No entries")
      return
    }
    const entries = root.service.entries
    const entry = entries[Math.floor(Math.random() * entries.length)]
    root.renderEntry(entry)
  }

  // Open the entry's source URL in the default browser (the "..." / more
  // action on each result row). Same detached-exec pattern as openRenderFolder.
  function openEntrySource(entry) {
    if (!entry || !entry.source) return
    // Only open http(s) URLs — never file://, magnet:, or other URI schemes.
    if (!root.sourceSchemeRe.test(entry.source || "")) return
    Quickshell.execDetached(["xdg-open", entry.source])
  }

  function showToast(msg) {
    root.toast = msg
    toastTimer.restart()
  }

  function openRenderFolder() {
    if (root.lastRenderPath === "") return
    const slash = root.lastRenderPath.lastIndexOf("/")
    if (slash < 1) return
    Quickshell.execDetached(["xdg-open", root.lastRenderPath.substring(0, slash)])
  }

  // Release the search field's focus so the focus-triggered dropdowns close
  // when the user clicks any interactive panel element (result/history card,
  // bookmark/share button, open-folder link). MouseAreas are not focusable, so
  // without this the field keeps focus and the dropdown stays open, blocking
  // navigation. The search field itself and the dropdown rows keep focus.
  function dismissSearch() {
    recordTimer.stop()
    searchField.focus = false
    keyCatcher.forceActiveFocus()
  }

  // Round-ended (pill) tooltip with the themed tooltip background, shared by
  // the result-row and metric tooltips (which override `fontFamily`/
  // `fontSize`). The header/folder hover buttons use AccentToolTip instead.
  component DhhToolTip: PanelToolTip {
    background: Rectangle { color: Color.tooltip.background; radius: 9999 }
  }

  // Accent-tinted tooltip for the header and folder hover buttons: the themed
  // DhhToolTip with the hover-disc accent background and X-text foreground,
  // centered below its host. `text` and `visible` are inherited from ToolTip.
  component AccentToolTip: DhhToolTip {
    panelForeground: root.xText
    background: Rectangle {
      color: Style.hoverFillFor(root.barForeground, root.xAccent)
      radius: 9999
    }
    x: (parent.width - implicitWidth) / 2
    y: parent.height + Style.spacing.sm
  }

  // X verified seal + 37signals logo pair, vertically centered on the
  // author/name line. Shared by the result-row author line (bodySmall) and
  // the header identity block (heading). `size` sizes the seal; `logoSize`
  // sizes the mark — they differ by a pixel in the compact row, match in the
  // header. The seal→logo gap mirrors the hosting Row's `spacing`.
  component VerifiedBadge: Item {
    required property int size
    property int logoSize: size
    readonly property int gap: parent.spacing
    readonly property int totalWidth: size + gap + logoSize

    width: totalWidth
    height: Math.max(size, logoSize)

    // Solid X verified seal (blue circle + white checkmark) matching the
    // render's badge SVG.
    Image {
      id: verifiedBadge
      width: size
      height: size
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      source: root.verifiedBadgeSource
      sourceSize: Qt.size(size * 2, size * 2)
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      smooth: true
    }

    // 37signals company logo beside the blue verified check. A thin (1px)
    // sharp-corner square border flush against the logo edge.
    Rectangle {
      width: logoSize
      height: logoSize
      anchors.left: verifiedBadge.right
      anchors.leftMargin: gap
      anchors.verticalCenter: parent.verticalCenter
      color: "transparent"
      border.width: 1
      border.color: root.xGray

      Image {
        anchors.fill: parent
        source: root.companyLogoSource
        sourceSize: Qt.size(32, 32)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
      }
    }
  }

  // Magnifier icon shared by the recent-search and suggestion dropdown rows.
  component MagnifierIcon: Image {
    width: Style.space(20)
    height: Style.space(20)
    source: root.searchIconSource
    sourceSize: Qt.size(24, 24)
    fillMode: Image.PreserveAspectFit
    asynchronous: true
    smooth: true
  }

  // Circular 34.75px hover-disc action button (X-style). Shared by the
  // author-line Grok + "..." cluster and the bottom bookmark/share pair: a
  // circular hover disc that appears on hover, a centered action icon with a
  // resting→hover source swap, a full-fill MouseArea, and a centered tooltip
  // below. `iconOpacity` dims the icon in place (used by the share button
  // while a render is in flight).
  component DiscIconButton: Item {
    id: disc

    required property string icon
    required property string iconHover
    required property size iconSourceSize
    required property string tooltip
    property real iconOpacity: 1.0
    signal activated()

    width: Style.spaceReal(34.75)
    height: Style.spaceReal(34.75)

    // Circular hover disc behind the icon, matching the stat icons' chrome.
    Rectangle {
      anchors.fill: parent
      radius: width / 2
      visible: discMouse.containsMouse
      color: Style.hoverFillFor(root.barForeground, root.xAccent)
    }

    Image {
      anchors.centerIn: parent
      width: root.xActionIconSize
      height: root.xActionIconSize
      source: discMouse.containsMouse ? iconHover : icon
      sourceSize: iconSourceSize
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      smooth: true
      opacity: iconOpacity
    }

    MouseArea {
      id: discMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: disc.activated()
    }

    DhhToolTip {
      visible: discMouse.containsMouse
      text: tooltip
      x: (parent.width - implicitWidth) / 2
      y: parent.height + Style.spacing.sm
      fontFamily: root.textFontFamily
      fontSize: Style.font.body
    }
  }

  // One result row, shared by the search-results list and the standalone
  // "History" list. Flat full-width X-style row: no card container, no
  // elevation — just content separated by a 1px hairline. In list context
  // (`inList`) it joins the selection and divider chrome and its actions
  // resolve by index; otherwise it copies or renders the entry directly.
  component ResultCard: Rectangle {
    id: card

    required property var entry
    property int cardIndex: -1
    required property string bodyHtml
    property bool inList: true
    property bool showDivider: true
    readonly property var counts: Fmt.engagementCounts(card.entry ? card.entry.text : "")

    width: bodyScroll.width
    height: cardColumn.implicitHeight + Style.spacing.md * 2
    radius: 0
    color: card.inList && root.selectedIndex === card.cardIndex
      ? Style.selectedFillFor(root.barForeground, root.xAccent)
      : "transparent"

    // Full-surface copy MouseArea. MUST be the first child (bottom of the
    // stacking order) so the action buttons above receive their own clicks.
    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: { if (card.inList) root.selectedIndex = card.cardIndex }
      onClicked: {
        if (card.inList) {
          root.service.recordRecentQuery(root.query.trim())
          root.copyEntryAt(card.cardIndex)
        } else root.copyEntry(card.entry)
        root.dismissSearch()
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

      // The body sits close under the name line (X-style); the outer
      // cardColumn spacing still separates this block from the action row.
      Row {
        width: parent.width
        spacing: Style.space(12)

        Image {
          sourceSize.width: Style.space(40)
          sourceSize.height: Style.space(40)
          source: root.avatarSource
          fillMode: Image.PreserveAspectFit
        }

        // Content column: author line -> body -> quote, with a small gap so the
        // body starts just under the name line (X-style).
        Column {
          width: parent.width - Style.space(40) - parent.spacing
          spacing: Style.spacing.sm

          // Author line: name/badge/logo/handle anchored left, Grok + "..."
          // cluster anchored flush right at the content column edge (x.com
          // geometry). The wrapper's height is the tallest child — the 34.75px
          // icon cluster — so the shorter text line centers vertically against
          // it. The cluster reuses the bottom action row's 34.75px circular
          // hover-disc geometry, so the "..." glyph sits flush under the share
          // glyph below.
          Item {
            width: parent.width
            height: headIconRow.height

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
                text: root.sectionTitle
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.textFontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
              }

              VerifiedBadge {
                id: authorBadge
                size: Style.font.bodySmall
                logoSize: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                width: Math.max(0, parent.width - authorName.implicitWidth - authorBadge.totalWidth - parent.spacing * 2)
                text: "@dhh" + (card.entry.date ? " · " + Fmt.formatDate(card.entry.date) : "")
                textFormat: Text.PlainText
                color: root.foreground
                opacity: root.opacitySecondary
                font.family: root.textFontFamily
                font.pixelSize: Style.font.bodySmall
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
              spacing: -Style.spaceReal(8)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter

              DiscIconButton {
                icon: root.grokIconSource
                iconHover: root.grokIconSourceHover
                iconSourceSize: Qt.size(33, 32)
                tooltip: root.renderImageTooltip
                onActivated: {
                  if (card.inList) root.renderEntryAt(card.cardIndex)
                  else root.renderEntry(card.entry)
                  root.dismissSearch()
                }
              }

              DiscIconButton {
                icon: root.dotsIconSource
                iconHover: root.dotsIconSourceHover
                iconSourceSize: Qt.size(40, 40)
                tooltip: "Open link"
                onActivated: {
                  root.openEntrySource(card.entry)
                  root.dismissSearch()
                }
              }
            }
          }

          // Plain body: a post with no reply/repost kind renders DHH's words
          // directly.
          Text {
            visible: card.entry.type !== "quote" && card.entry.kind !== "reply" && card.entry.kind !== "repost"
            width: parent.width
            text: card.bodyHtml
            textFormat: Text.RichText
            color: root.foreground
            font.family: root.textFontFamily
            font.pixelSize: Style.font.body
            lineHeight: 1.3
            wrapMode: Text.WordWrap
          }

          // Reply/repost: both render DHH's body followed by the original post
          // as a bordered quoted card (author + handle + body), matching x.com's
          // quote-post style with no "replying to" line. The original post lives
          // in context and is not the search target, so its body is escaped, not
          // highlight-wrapped.
          Column {
            visible: card.entry.kind === "reply" || card.entry.kind === "repost"
            width: parent.width
            spacing: Style.spacing.md

            Text {
              width: parent.width
              text: card.bodyHtml
              textFormat: Text.RichText
              color: root.foreground
              font.family: root.textFontFamily
              font.pixelSize: Style.font.body
              lineHeight: 1.3
              wrapMode: Text.WordWrap
            }

            Rectangle {
              width: parent.width
              height: replyQuoteColumn.implicitHeight + Style.space(12) * 2
              radius: 16
              border.width: 1
              border.color: root.xDivider
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
                    source: root.contextAvatarUrlFor(card.entry.context && card.entry.context.handle)
                    fallbackSource: root.defaultAvatarSource
                    anchors.verticalCenter: parent.verticalCenter
                  }
                  Text {
                    id: quoteAuthorName
                    text: card.entry.context && card.entry.context.author ? card.entry.context.author : ""
                    textFormat: Text.PlainText
                    color: root.foreground
                    font.family: root.textFontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                  }
                  Text {
                    width: parent.width - Style.space(20) - Style.spacing.xs * 2 - quoteAuthorName.width
                    text: card.entry.context && card.entry.context.handle ? card.entry.context.handle + (card.entry.context.date ? " · " + Fmt.formatDate(card.entry.context.date) : "") : ""
                    textFormat: Text.PlainText
                    color: root.xGray
                    font.family: root.textFontFamily
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideRight
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }

                Text {
                  width: parent.width
                  text: card.entry.context && card.entry.context.text ? Fmt.escapeHtml(card.entry.context.text) : (card.entry.kind === "repost" ? Fmt.escapeHtml(card.entry.text) : "")
                  textFormat: Text.RichText
                  color: root.foreground
                  font.family: root.textFontFamily
                  font.pixelSize: Style.font.body
                  lineHeight: 1.3
                  wrapMode: Text.WordWrap
                }
              }
            }
          }

          // Quote: nested "quoted content" card — rounded container with a subtle
          // border and slightly different background, matching X's quoted-post
          // look. The quote text lives inside the container; the author chrome
          // above stays as the outer post.
          Rectangle {
            visible: card.entry.type === "quote"
            width: parent.width
            height: quoteColumn.implicitHeight + Style.spacing.sm * 2
            radius: Style.cornerRadius
            border.width: 1
            border.color: Util.alpha(root.barForeground, 0.15)
            color: Util.alpha(root.barForeground, 0.04)

            Column {
              id: quoteColumn
              width: parent.width - Style.spacing.sm * 2
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.xxs

              Text {
                width: parent.width
                text: card.bodyHtml
                textFormat: Text.RichText
                color: root.foreground
                font.family: root.textFontFamily
                font.pixelSize: Style.font.body
                lineHeight: 1.3
                wrapMode: Text.WordWrap
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
        anchors.leftMargin: root.contentIndent
        anchors.right: parent.right
        spacing: 0

        ActionMetric {
          iconSource: root.replyIconSource
          iconSourceHover: root.replyIconSourceHover
          countText: Fmt.formatCount(card.counts.reply)
          tooltip: "Reply"
          Layout.fillWidth: true
          Layout.preferredWidth: 0
          clickable: true
          onClicked: {
            root.openEntrySource(card.entry)
            root.dismissSearch()
          }
        }
        ActionMetric {
          iconSource: root.repostIconSource
          iconSourceHover: root.repostIconSourceHover
          countText: Fmt.formatCount(card.counts.repost)
          tooltip: "Repost"
          Layout.fillWidth: true
          Layout.preferredWidth: 0
          clickable: true
          onClicked: {
            if (card.inList) root.renderEntryAt(card.cardIndex)
            else root.renderEntry(card.entry)
            root.dismissSearch()
          }
        }
        ActionMetric {
          iconSource: root.likeIconSource
          iconSourceHover: root.likeIconSourceHover
          countText: Fmt.formatCount(card.counts.like)
          tooltip: "Like"
          Layout.fillWidth: true
          Layout.preferredWidth: 0
        }
        ActionMetric {
          iconSource: root.viewsIconSource
          iconSourceHover: root.viewsIconSourceHover
          countText: Fmt.formatCount(card.counts.views)
          tooltip: "Views"
          Layout.fillWidth: true
          Layout.preferredWidth: 0
        }

        Row {
          spacing: -Style.spaceReal(8)

          // Flat trailing action icons (X-style bookmark/share): 18.75px muted
          // gray, turning X-blue on hover, each on a 34.75px circular
          // hover-disc hit target (DiscIconButton).
          DiscIconButton {
            icon: root.bookmarkIconSource
            iconHover: root.bookmarkIconSourceHover
            iconSourceSize: Qt.size(24, 24)
            tooltip: "Copy text"
            onActivated: {
              if (card.inList) root.copyEntryAt(card.cardIndex)
              else root.copyEntry(card.entry)
              root.dismissSearch()
            }
          }

          DiscIconButton {
            icon: root.shareIconSource
            iconHover: root.shareIconSourceHover
            iconSourceSize: Qt.size(24, 24)
            tooltip: root.renderImageTooltip
            iconOpacity: (root.renderingText !== "" && card.entry && card.entry.text === root.renderingText) ? root.dimmedOpacity : 1.0
            onActivated: {
              if (card.inList) root.renderEntryAt(card.cardIndex)
              else root.renderEntry(card.entry)
              root.dismissSearch()
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
      color: root.xDivider
    }
  }

  // One engagement metric: an X action icon (outlined SVG, #71767B resting,
  // #1D9BF0 on hover) plus an optional count, sized to the render's 18.75px
  // `.action-icon` and 13px `.count`. Used four-up in the ResultCard action
  // row (reply/repost/like/views). Hover-only by default — its MouseArea
  // accepts no buttons, so clicks still fall through to the full-surface copy
  // MouseArea while hover still drives the tooltip. Setting `clickable` makes
  // it accept left-clicks and emit `clicked` instead (used by repost to render
  // the shareable image). Vertically centered against the taller trailing
  // bookmark/share buttons sharing the row.
  component ActionMetric: Row {
    property string iconSource: ""
    property string iconSourceHover: ""
    property string countText: ""
    property string tooltip: ""
    property bool clickable: false
    signal clicked()

    spacing: Style.spacing.sm
    Layout.alignment: Qt.AlignVCenter

    // The disc is a child of this Item, not the Row — a Row forbids horizontal
    // anchors on direct children, so centering the disc on the icon inside a
    // plain Item keeps the Row's own horizontal layout intact (same pattern as
    // HeaderIconButton).
    Item {
      width: root.xActionIconSize
      height: root.xActionIconSize
      anchors.verticalCenter: parent.verticalCenter

      // Circular hover disc behind the stat icon, matching x.com's hover
      // chrome. Declared before the icon so the icon draws on top.
      Rectangle {
        width: Style.space(30)
        height: Style.space(30)
        radius: width / 2
        anchors.centerIn: parent
        visible: metricHover.containsMouse
        color: Style.hoverFillFor(root.barForeground, root.xAccent)
      }

      // X outlined action icon, resting #71767B and turning the exact X-blue
      // #1D9BF0 on hover via a pre-rendered blue SVG variant. anchors.fill
      // keeps metricIcon.width set so the tooltip below centers on the icon.
      Image {
        id: metricIcon
        anchors.fill: parent
        source: metricHover.containsMouse ? iconSourceHover : iconSource
        sourceSize: Qt.size(26, 26)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
      }
    }

    Text {
      visible: countText !== ""
      anchors.verticalCenter: parent.verticalCenter
      text: countText
      textFormat: Text.PlainText
      color: root.xGray
      font.family: root.textFontFamily
      font.pixelSize: Style.font.subtitle
    }

    MouseArea {
      id: metricHover
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
      acceptedButtons: clickable ? Qt.LeftButton : Qt.NoButton
      onClicked: { if (clickable) parent.clicked() }
    }

    DhhToolTip {
      visible: metricHover.containsMouse
      text: tooltip
      x: (metricIcon.width - implicitWidth) / 2
      y: parent.height + Style.spacing.sm
      fontFamily: root.textFontFamily
      fontSize: Style.font.body
    }
  }

  // Circular avatar rendered via a MultiEffect mask (Rectangle+clip does not
  // round the child Image in this Qt version). Same pattern as the shell's
  // image-picker: a hidden Shape layer is the mask source. Used only by the
  // ResultCard rows. `size` is the diameter in logical px; the inner Image is
  // loaded at 2x for retina.
  component CircularAvatar: Item {
    id: avatar

    property int size: Style.space(40)
    property string source: ""
    property string fallbackSource: ""

    width: size
    height: size

    Item {
      id: avatarMask
      anchors.fill: parent
      visible: false
      layer.enabled: true

      Shape {
        anchors.fill: parent
        antialiasing: true
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
          fillColor: "white"
          strokeColor: "transparent"
          startX: avatarMask.width
          startY: avatarMask.height / 2
          PathArc {
            x: 0
            y: avatarMask.height / 2
            radiusX: avatarMask.width / 2
            radiusY: avatarMask.height / 2
            useLargeArc: true
          }
          PathArc {
            x: avatarMask.width
            y: avatarMask.height / 2
            radiusX: avatarMask.width / 2
            radiusY: avatarMask.height / 2
            useLargeArc: true
          }
        }
      }
    }

    Item {
      anchors.fill: parent
      layer.enabled: true
      layer.smooth: true
      layer.effect: MultiEffect {
        maskEnabled: true
        maskSource: avatarMask
        maskThresholdMin: 0.3
        maskSpreadAtMin: 0.3
      }

      Image {
        anchors.fill: parent
        source: avatar.source
        sourceSize: Qt.size(avatar.size * 2, avatar.size * 2)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
        onStatusChanged: {
          if (status === Image.Error && avatar.fallbackSource !== "") {
            source = avatar.fallbackSource
          }
        }
      }
    }
  }

  // Header icon button: a circular hover disc behind an action icon with a
  // below-centered tooltip. Shared by the back / grok / search header actions
  // so their hover chrome, hit target, and tooltip can't drift apart. `source`
  // is the icon URL, `tooltip` the hover label, and `clicked` fires on press.
  component HeaderIconButton: Item {
    id: btn

    property string source
    property size sourceSize: Qt.size(44, 44)
    property string tooltip
    signal clicked()

    width: Style.spacing.controlHeight
    height: Style.spacing.controlHeight

    // Hover circle: soft light disc behind the icon (x.com header-button
    // hover), sized ~1.5x the 22px icon and centered on the hit target.
    // Declared before the icon so the icon draws on top.
    Rectangle {
      width: Style.space(34)
      height: Style.space(34)
      radius: width / 2
      anchors.centerIn: parent
      visible: mouse.containsMouse
      color: Style.hoverFillFor(root.barForeground, root.xAccent)
    }

    Image {
      width: Style.space(22)
      height: Style.space(22)
      anchors.centerIn: parent
      source: btn.source
      sourceSize: btn.sourceSize
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      smooth: true
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: btn.clicked()
    }

    AccentToolTip {
      visible: mouse.containsMouse
      text: btn.tooltip
    }
  }

  // Counter-offset wrapper: bodyColumn is inset Style.spacing.lg from each
  // side, so full-bleed children (divider, results list, history list) span
  // the full bodyScroll width by shifting left by the same inset and widening
  // to bodyScroll.width. A Column keeps the vertical flow of bodyColumn (its
  // height follows its content) and honors `visible`, so a hidden block still
  // collapses out of the layout.
  component FullBleed: Column {
    x: -Style.spacing.lg
    width: bodyScroll.width
  }

  // 1px full-width hairline divider, X's solid #2F3336. Shared by the
  // history and results blocks to separate them from the content above.
  component HairlineDivider: Rectangle {
    height: 1
    color: root.xDivider
    width: parent.width
  }

  ListModel { id: resultModel }

  Timer {
    id: searchTimer
    interval: 80
    repeat: false
    onTriggered: root.runSearch()
  }

  Timer {
    id: recordTimer
    interval: 3000
    repeat: false
    onTriggered: { if (root.service) root.service.recordRecentQuery(root.query.trim()) }
  }

  Timer {
    id: toastTimer
    interval: 2000
    onTriggered: root.toast = ""
  }

  // Safety net: if the render subprocess hangs and onExited never fires, clear
  // the busy state so the UI never stays dim, kill the stuck process so the
  // next render starts clean, and surface a specific message. onExited fires
  // right after the kill and is gated on renderTimedOut so it cannot overwrite
  // this message with the generic "Render failed".
  Timer {
    id: renderWatchdog
    interval: 15000
    repeat: false
    onTriggered: {
      root.renderTimedOut = true
      if (root.service) {
        root.service.generating = false
      }
      root.renderingText = ""
      root.showToast("Render timed out")
      if (renderProcess.running) renderProcess.signal(15)
    }
  }

  WorkerScript {
    id: searchWorker
    source: "SearchWorker.js"
    onMessage: (msg) => {
      if (msg.type === "init") {
        root.workerReady = true
        return
      }
      if (msg.type === "trending") {
        if (root.service) root.service.trendingTerms = msg.trendingTerms || []
        return
      }
      if (msg.query !== root.query) return
      resultModel.clear()
      const hits = msg.results || []
      hits.forEach(hit => {
        const picked = Search.pickEntry(hit)
        // Optional fields must be non-undefined so the delegate's string-typed
        // required properties bind cleanly against the ListModel roles.
        picked.title = picked.title || ""
        picked.domain = picked.domain || ""
        picked.date = picked.date || ""
        picked.context = picked.context || {}
        picked.kind = picked.kind || ""
        picked.textHtml = root.highlightQuery(Search.stripReplyMention(hit.text, hit.context && hit.context.handle ? hit.context.handle : ""), root.query)
        resultModel.append(picked)
      })
      root.setResultStatus(typeof msg.total === "number" ? msg.total : hits.length)
      root.selectedIndex = 0
      // Populate suggestions AFTER the result list so the dropdown opens only
      // once the list has settled: the append loop above churns
      // bodyScroll.contentY, which dismisses the dropdown.
      root.suggestions = root.orderSuggestions(msg.suggestions || [])
    }
  }

  Connections {
    target: root.service
    // No `enabled` guard — if service is loaded before the Panel gets it
    // injected, entriesLoadedChanged fires while the Connections is still
    // disabled and ensureWorkerInit is missed, leaving workerReady=false
    // permanently and a stale worker state that segfaults on the first real
    // search message.
    function onEntriesLoadedChanged() {
      if (root.service && root.service.entriesLoaded) root.ensureWorkerInit()
    }
  }

  Process {
    id: renderProcess
    stdout: SplitParser {
      onRead: (line) => {
        if (root.service) root.service.renderPathDelivered = true
        root.lastRenderPath = line
      }
    }
    // Exit and stream-finished have no guaranteed order. A failed exit posts a
    // generic message; when the collector lands, replace it with the specific
    // stderr. A successful render may still log a clipboard-copy warning, but
    // by then the stdout reader has set renderPathDelivered, so the warning is
    // not surfaced.
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.renderStderr = String(text || "").trim()
        if (root.renderStderr !== "" && root.service && !root.service.renderPathDelivered) {
          root.showToast(root.renderStderr)
        }
      }
    }
    onExited: (exitCode) => {
      renderWatchdog.stop()
      root.renderingText = ""
      if (root.service) {
        root.service.generating = false
        if (exitCode !== 0 && !root.renderTimedOut) {
          const err = root.renderStderr !== "" ? root.renderStderr : "Render failed"
          root.showToast(err)
        }
      }
      root.renderTimedOut = false
    }
  }

  KeyboardPanel {
    id: keyboardPanel
    padding: 0
    anchorItem: root.anchorItem
    owner: root.barOwner
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: keyboardPanel.fittedContentWidth(Style.space(520))
    contentHeight: keyboardPanel.fittedContentHeight(root.contentTotalHeight, Style.space(640))
    // Neutral x.com hairline border in place of the themed purple. The
    // KeyboardPanel default resolves the theme's `popups.border` token
    // (hyprland.active-border -> #ab92fc) regardless of any fallback color, so
    // a flat spec pins the color directly while keeping the same width.
    borderSpec: Border.flat(root.xDivider, Math.max(1, Style.space(2)))

    // Opaque x.com "Lights Out" backdrop, declared first so it paints behind
    // every child. KeyboardPanel's card fill is themed (purple) and exposes no
    // color override, so black is layered here over the card, filling the
    // content holder (already inset by the border width). Rounded to the
    // card's inner radius so it never pokes out of the rounded corners when
    // Hyprland decoration rounding is enabled.
    Rectangle {
      anchors.fill: parent
      radius: Math.max(0, Style.cornerRadius - Border.top(keyboardPanel.borderSpec))
      color: "#000000"
    }

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: searchField.activeFocus
      onCloseRequested: root.close()
      onMoveRequested: (dx, dy) => {
        if (dy !== 0) root.moveSelection(dy)
      }
      onActivateRequested: {
        if (root.query.trim() === "") return
        root.service.recordRecentQuery(root.query.trim())
        root.copyEntryAt(root.selectedIndex)
      }
      onTabRequested: (direction) => { root.switchPanel(direction) }

      MouseArea {
        anchors.fill: parent
        z: -1
        onPressed: keyCatcher.forceActiveFocus()
      }

      // Sticky x.com-style profile header, overlaid above the scroll content
      // (bodyScroll fills the panel, so rows scroll up beneath this strip).
      // When bodyScroll.contentY > 0 (content has scrolled beneath it) a
      // blurred capture of that content fades in behind the identity block,
      // tinted by a semi-transparent X-dark backdrop, so scrolled rows read
      // through a frosted band; at the very top it is fully transparent and
      // blends into the panel surface. The backdrop/blur visibility keys off
      // contentY separately from the header text so scrolling never fades the
      // identity block itself.
      Item {
        id: headerBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: headerLayout.height + Style.spacing.lg + Style.spacing.sm + 1
        // Overlay above bodyScroll: content scrolls up beneath this strip.
        z: 1

        // Semi-transparent dark backdrop for the scrolled header, matching
        // x.com's frosted profile strip. A fixed dark overlay reads
        // consistently on every theme; alpha-blending the themed foreground
        // would invert the tint on dark themes.
        Rectangle {
          anchors.fill: parent
          color: Util.alpha("#000000", 0.45)
          opacity: bodyScroll.contentY >= root.headerRevertThreshold ? 1 : 0
        }

        // Header: back arrow, name + verified badge + post count, then random
        // and search actions flush right. The identity column fills the
        // remaining width, pushing the two action buttons to the far right. On
        // scroll (contentY > 0) the grok/search buttons hide and a display-only
        // "Following" pill takes their place flush right, matching x.com's
        // scrolled profile header.
        RowLayout {
          id: headerLayout
          anchors.top: parent.top
          anchors.topMargin: Style.spacing.lg
          anchors.left: parent.left
          anchors.leftMargin: Style.space(16)
          anchors.right: parent.right
          anchors.rightMargin: Style.space(24)
          spacing: Style.spacing.md
          // Fixed row height: keeps the header height (and the layout beneath
          // it) constant regardless of which right-side element is showing.
          height: Style.space(44)

          // Back arrow: closes the popup (same path as the Esc handler).
          HeaderIconButton {
            source: root.backIconSource
            tooltip: "Close"
            onClicked: root.close()
          }

          // Identity block: bold name + blue verified badge, then a gray
          // post count. Fills the row so the actions sit flush right.
          // Left margin widens the back-arrow -> name gap to match x.com's
          // ~2.8x arrow-width spacing (the RowLayout `spacing` alone is too
          // tight at ~0.9x).
          Column {
            Layout.fillWidth: true
            Layout.leftMargin: Style.space(24)
            spacing: Style.spacing.xxs

            Row {
              width: parent.width
              spacing: Style.spacing.xs

              Text {
                text: root.sectionTitle
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.textFontFamily
                font.pixelSize: Style.font.heading
                font.bold: true
                elide: Text.ElideRight
              }

              VerifiedBadge {
                size: Style.font.heading
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Text {
              width: parent.width
              text: root.service ? root.service.postCount : ""
              textFormat: Text.PlainText
              color: root.xGray
              font.family: root.textFontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }
          }

          // Grok button: renders a random entry as a shareable image. Hidden
          // on scroll, where x.com swaps the action icons for the Following pill.
          HeaderIconButton {
            source: root.grokIconSourceLight
            sourceSize: Qt.size(33, 32)
            tooltip: "Render random"
            visible: bodyScroll.contentY < root.headerRevertThreshold
            onClicked: root.renderRandomEntry()
          }

          // Search button: focuses the search field (opens the focus-triggered
          // recent-search dropdown). Hidden on scroll alongside the Grok button.
          HeaderIconButton {
            source: root.searchIconSource
            tooltip: "Search"
            visible: bodyScroll.contentY < root.headerRevertThreshold
            onClicked: searchField.forceActiveFocus()
          }

          // x.com "Following" pill, shown only once content has scrolled beneath
          // the header (mirroring the real scrolled profile header). Display-only
          // visual parity — a quotes plugin has no follow concept, so there is
          // deliberately no click action and no MouseArea.
          Rectangle {
            visible: bodyScroll.contentY >= root.headerRevertThreshold
            Layout.alignment: Qt.AlignVCenter
            height: Style.space(32)
            width: followingLabel.implicitWidth + Style.space(32)
            radius: height / 2
            color: "transparent"
            border.width: 1
            border.color: root.xGray

            Text {
              id: followingLabel
              anchors.centerIn: parent
              text: "Following"
              textFormat: Text.PlainText
              color: root.xText
              font.family: root.textFontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }
          }
        }
      }

      Flickable {
        id: bodyScroll
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true
        contentWidth: width
        contentHeight: root.contentTotalHeight
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        QQC.ScrollBar.vertical: QQC.ScrollBar { policy: QQC.ScrollBar.AsNeeded }

        // Full-surface click-catcher, declared FIRST so it sits at the bottom
        // of the Flickable's content stacking order. Every interactive child
        // (search field, result cards, bookmark/share/open-folder links) is
        // declared after it and keeps its own clicks. Clicks that fall through
        // — spacing gaps, empty results space — land here and dismiss the
        // search dropdowns. Like bodyColumn, Flickable reparents it into
        // contentItem, so anchors.fill covers the full scrollable content, not
        // just the viewport. (The keyCatcher-level z:-1 MouseArea sits behind
        // bodyScroll and never receives these clicks.)
        MouseArea {
          anchors.fill: parent
          onClicked: root.dismissSearch()
        }

        Column {
          id: bodyColumn
          x: Style.spacing.lg
          y: headerBar.height + Style.spacing.lg
          width: bodyScroll.width - Style.spacing.lg * 2
          spacing: Style.spacing.sm

          // Extra vertical clearance above and below the search pill, matching
          // x.com's spacing (the field no longer sits tight against the header
          // divider above or the content below). A Column (not Item) so the
          // top/bottom padding properties exist.
          Column {
            width: parent.width
            topPadding: Style.spacing.xs
            bottomPadding: Style.spacing.xs

            TextField {
              id: searchField
              width: parent.width
              height: Style.space(38)
              text: root.query
              placeholderText: "Search"
              foreground: root.foreground
              accent: root.xAccent
              // X explore-style pill: icon sits ~16px from the left edge, then a
              // ~16px icon and ~12px gap before the text; ~16px right padding.
              leftPadding: Style.space(44)
              rightPadding: Style.space(16)
              topPadding: Style.space(11)
              bottomPadding: Style.space(11)
              placeholderTextColor: Util.alpha(root.barForeground, 0.5)
              font.family: root.textFontFamily
              font.pixelSize: Style.space(15)
              font.weight: Font.Normal
              // Pill surface: subtle theme-aware fill, a 1px muted ring at rest,
              // and the same 1px ring in X-blue on focus. Radius caps at half
              // height -> true pill.
              background: Rectangle {
                radius: height / 2
                color: Util.alpha(root.barForeground, 0.08)
                border.width: 1
                border.color: searchField.activeFocus ? root.xAccent : root.xMuted
              }
              onTextChanged: {
                root.query = text
                root.scheduleSearch()
              }
              // Re-show suggestions when the field regains focus with a query
              // still typed but no suggestions (e.g. after a completed
              // selection cleared them); the debounced search repopulates both
              // results and suggestions.
              onActiveFocusChanged: {
                if (activeFocus && root.query.trim() !== "" && root.suggestions.length === 0) root.scheduleSearch()
              }
              // Arrow-key navigation is gated on results being present; the
              // clear button below empties the field.
              Keys.priority: Keys.BeforeItem
              Keys.onPressed: (event) => {
                if (resultModel.count === 0) return
                if (event.key === Qt.Key_Down) { root.moveSelection(1); event.accepted = true }
                else if (event.key === Qt.Key_Up) { root.moveSelection(-1); event.accepted = true }
              }
              Keys.onEscapePressed: {
                searchField.focus = false
                keyCatcher.forceActiveFocus()
              }

              // Search icon: ~16px, muted gray, ~16px from the left edge.
              Image {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(16)
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(16)
                height: Style.space(16)
                source: root.searchIconSource
                sourceSize: Qt.size(24, 24)
                fillMode: Image.PreserveAspectFit
                opacity: root.opacitySecondary
                asynchronous: true
                smooth: true
              }

              // Clear button: solid white filled circle with a black "×" icon,
              // matching x.com's search clear button. ~17px diameter (roughly
              // half the 38px field height), ~16px from the right edge.
              Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: Style.space(16)
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(17)
                height: Style.space(17)
                radius: width / 2
                visible: searchField.text !== ""
                color: "#FFFFFF"

                Image {
                  anchors.centerIn: parent
                  width: Style.space(11)
                  height: Style.space(11)
                  source: root.clearSearchIconSource
                  sourceSize: Qt.size(384, 512)
                  fillMode: Image.PreserveAspectFit
                  asynchronous: true
                  smooth: true
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    searchField.text = ""
                    searchField.forceActiveFocus()
                  }
                }
              }
            }
          }

          // Render feedback: full-width preview of the rendered PNG, with a
          // short status line and a folder icon button in a compact row below.
          // Appears as soon as a render prints its output path and stays
          // visible regardless of the query so clearing the search still shows
          // the last rendered image.
          Column {
            width: parent.width
            visible: root.lastRenderPath !== ""
            spacing: Style.spacing.xxs

            // Full-width preview, clickable to open the output folder. The
            // height binding MUST null-guard sourceSize — an unguarded deref
            // crashes the panel while the image is still loading.
            MouseArea {
              width: parent.width
              height: renderPreview.height
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.openRenderFolder()
                root.dismissSearch()
              }

              Image {
                id: renderPreview
                width: parent.width
                source: Util.fileUrl(root.lastRenderPath)
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
                // Fit the panel width, preserve aspect ratio, and cap the height
                // so a very tall entry does not push the panel off-screen.
                height: renderPreview.sourceSize && renderPreview.sourceSize.width > 0
                  ? Math.min(Style.space(240), renderPreview.sourceSize.height * (renderPreview.width / renderPreview.sourceSize.width))
                  : Style.space(160)
              }
            }

            // Compact status row below the preview: the status text fills the
            // gap and the folder icon button sits flush right.
            Row {
              width: parent.width
              spacing: Style.spacing.md

              Text {
                width: parent.width - Style.spacing.controlHeight - Style.spacing.md
                anchors.verticalCenter: parent.verticalCenter
                text: "Saved · Copied to clipboard"
                textFormat: Text.PlainText
                color: root.foreground
                opacity: root.opacitySecondary
                font.family: root.textFontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }

              // Folder icon button: flat muted gray icon with a 28px hit
              // target, matching the ResultCard action buttons.
              Item {
                width: Style.spacing.controlHeight
                height: Style.spacing.controlHeight
                anchors.verticalCenter: parent.verticalCenter

                Image {
                  anchors.centerIn: parent
                  width: root.xActionIconSize
                  height: root.xActionIconSize
                  source: folderBtnMouse.containsMouse ? root.folderIconSourceHover : root.folderIconSource
                  sourceSize: Qt.size(512, 512)
                  fillMode: Image.PreserveAspectFit
                  asynchronous: true
                  smooth: true
                }

                MouseArea {
                  id: folderBtnMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.openRenderFolder()
                    root.dismissSearch()
                  }
                }

                AccentToolTip {
                  visible: folderBtnMouse.containsMouse
                  text: "Open folder"
                }
              }
            }
          }

          FullBleed {
            visible: root.query.trim() === "" && root.service && root.service.historyEntries.length > 0
            spacing: Style.spacing.xxs

            HairlineDivider {}

            // History list. Eager Repeater (not a ListView): the outer
            // bodyScroll Flickable handles scrolling, so a ListView would add
            // unused scroll machinery for zero benefit. Most-recent-first order.
            Repeater {
              model: root.service && root.service.historyEntries ? root.service.historyEntries : []

              delegate: ResultCard {
                required property var modelData
                required property int index

                entry: modelData
                bodyHtml: root.highlightQuery(Search.stripReplyMention(modelData.text, modelData.context && modelData.context.handle ? modelData.context.handle : ""), "")
                inList: false
                showDivider: index < root.service.historyEntries.length - 1
              }
            }
          }

          Row {
            width: parent.width
            visible: root.query.trim() !== ""
            spacing: Style.spacing.sm
            topPadding: Style.spacing.sm
            bottomPadding: Style.spacing.sm

            Text {
              id: statusLabel
              visible: resultModel.count > 0
              width: Math.min(Style.space(260), implicitWidth)
              text: root.statusText
              textFormat: Text.PlainText
              color: root.foreground
              opacity: root.opacitySecondary
              font.family: root.textFontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }

            Item {
              width: Math.max(0, parent.width - (statusLabel.visible ? statusLabel.width : 0) - keyboardHint.implicitWidth - Style.spacing.sm)
              height: 1
            }

            Text {
              id: keyboardHint
              text: resultModel.count > 0 ? "↑ ↓ navigate · Enter copy" : ""
              textFormat: Text.PlainText
              color: root.foreground
              opacity: root.opacitySecondary
              font.family: root.textFontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          Item {
            width: parent.width
            height: Style.space(96)
            visible: root.query.trim() !== "" && resultModel.count === 0

            Text {
              anchors.centerIn: parent
              text: root.statusText
              textFormat: Text.PlainText
              color: root.foreground
              opacity: root.opacitySecondary
              font.family: root.textFontFamily
              font.pixelSize: Style.font.body
            }
          }

          FullBleed {
            visible: root.query.trim() !== "" && resultModel.count > 0
            HairlineDivider {}
          }

          FullBleed {
            visible: root.query.trim() !== "" && resultModel.count > 0
            ListView {
              id: resultScroll
              width: parent.width
              height: Math.max(Style.space(96), contentHeight)
              clip: true
              model: resultModel
              spacing: 0
              boundsBehavior: Flickable.StopAtBounds

              delegate: ResultCard {
                required property string text
                required property string type
                required property string title
                required property string domain
                required property string source
                required property var date
                required property var context
                required property string kind
                required property string textHtml
                required property int index

                entry: ({ text: text, type: type, source: source, date: date, context: context, kind: kind, title: title, domain: domain })
                cardIndex: index
                bodyHtml: textHtml
                showDivider: index < resultModel.count - 1
              }
            }
          }

          Text {
            width: parent.width
            visible: root.toast !== ""
            text: root.toast
            textFormat: Text.PlainText
            color: root.xAccent
            font.family: root.textFontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }

  // Floating search dropdown surface, shared by the recent-searches and
  // word-autocomplete dropdowns. Reparented into `keyCatcher` (the panel
  // content root) — `root` lives in the bar's window inside an invisible
  // Loader, so a dropdown parented there can never render over the separate
  // layer-shell panel, and cross-window anchors never resolve. Visibility is
  // purely declarative (`visible: shouldShow`) so it re-evaluates on every
  // state change — no imperative open/close/refresh and no signal handler to
  // fire. Geometry is a reactive binding keyed off `bodyScroll.contentY` (the
  // field lives inside `bodyScroll`, so its keyCatcher-space position moves
  // with the scroll), not a one-shot snapshot.
  component SearchDropdown: Rectangle {
    id: dropdown

    parent: keyCatcher
    z: 100
    radius: Style.space(12)
    color: "#000000"
    visible: shouldShow

    // Whether the dropdown should be shown right now; each usage site binds
    // this to its own condition (recent searches vs word autocomplete).
    property bool shouldShow: false

    // Row content supplied by the usage site (header + rows).
    default property alias content: dropdown.data

    // mapToItem is one-shot, so read bodyScroll.contentY inside this binding
    // to make it re-run on every scroll — the only thing that moves the field
    // in keyCatcher space (contentX is always 0).
    readonly property point fieldBottom: {
      bodyScroll.contentY
      return searchField.mapToItem(keyCatcher, 0, searchField.height)
    }
    x: fieldBottom.x
    y: fieldBottom.y + Style.spacing.xxs
    width: searchField.width
    height: 0
  }

  // Focus-triggered recent-search dropdown, matching x.com's search-history
  // surface.
  SearchDropdown {
    height: recentColumn.implicitHeight + Style.space(16) * 2
    shouldShow: searchField.activeFocus
      && root.query.trim() === ""
      && root.service
      && root.service.recentQueries.length > 0

    Column {
      id: recentColumn
      anchors.fill: parent
      anchors.margins: Style.space(16)
      spacing: Style.space(16)

      // "Recent" caption with a blue "Clear all" link on the right.
      Item {
        width: parent.width
        height: Style.space(24)

        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "Recent"
          textFormat: Text.PlainText
          color: root.foreground
          font.family: root.textFontFamily
          font.pixelSize: Style.space(15)
          font.bold: true
        }

        Item {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: clearAllText.implicitWidth
          height: parent.height

          Text {
            id: clearAllText
            anchors.verticalCenter: parent.verticalCenter
            text: "Clear all"
            textFormat: Text.PlainText
            color: root.xAccent
            font.family: root.textFontFamily
            font.pixelSize: Style.space(15)
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (root.service) root.service.clearRecentQueries()
            }
          }
        }
      }

      Repeater {
        model: root.service ? root.service.recentQueries : []
        delegate: Item {
          required property string modelData

          width: recentColumn.width
          height: Style.space(32)

          // Full-row click (bottom of the stack so the remove button above
          // keeps its own click): fill the field, which triggers the existing
          // onTextChanged search and closes the dropdown as the query becomes
          // non-empty.
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              searchField.text = modelData
              searchField.forceActiveFocus()
            }
          }

          // Magnifier icon.
          MagnifierIcon {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          // Query text.
          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(32)
            anchors.right: removeBtn.left
            anchors.rightMargin: Style.spacing.sm
            anchors.verticalCenter: parent.verticalCenter
            text: modelData
            textFormat: Text.PlainText
            color: root.foreground
            font.family: root.textFontFamily
            font.pixelSize: Style.space(15)
            elide: Text.ElideRight
          }

          // Bare "×" remove icon at the far right (no circle/background).
          Item {
            id: removeBtn
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(28)
            height: Style.space(28)

            Image {
              anchors.centerIn: parent
              width: Style.space(18)
              height: Style.space(18)
              source: root.removeRecentIconSource
              sourceSize: Qt.size(384, 512)
              fillMode: Image.PreserveAspectFit
              asynchronous: true
              smooth: true
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (root.service) root.service.removeRecentQuery(modelData)
              }
            }
          }
        }
      }
    }
  }

  // Word-autocomplete suggestion dropdown, matching x.com's search suggestion
  // surface. Shown while typing (query non-empty); each row fills the field and
  // runs the search via the existing onTextChanged handler.
  SearchDropdown {
    height: suggestionColumn.implicitHeight + Style.space(16) * 2
    shouldShow: searchField.activeFocus
      && root.query.trim() !== ""
      && root.suggestions.length > 0

    Column {
      id: suggestionColumn
      anchors.fill: parent
      anchors.margins: Style.space(16)
      spacing: Style.space(16)

      Repeater {
        model: root.suggestions
        delegate: Item {
          required property string modelData

          width: suggestionColumn.width
          height: Style.space(32)

          // Full-row click (bottom of the stack so any later child keeps its
          // own click): fill the field, which triggers the existing onTextChanged
          // search, then re-focus the field for the next keystroke.
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.service.recordRecentQuery(modelData)
              if (searchField.text !== modelData) searchField.text = modelData
              root.suggestions = []
              searchField.forceActiveFocus()
            }
          }

          // Magnifier icon.
          MagnifierIcon {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          // Query text (bold) with a small gray "Trending" subtitle stacked
          // underneath, matching x.com's search-suggestion rows. The subtitle
          // only appears when the term is currently trending; other rows show
          // just the magnifier and query text.
          Column {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(32)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              width: parent.width
              // Bold only the characters NOT matching the typed query (the
              // remainder after a leading, case-insensitive prefix per
              // suggestWords); the matched prefix stays regular weight. Both
              // portions are escaped before wrapping.
              text: {
                const q = root.query.trim()
                const n = q.length
                const matched = n > 0 && modelData.toLowerCase().indexOf(q.toLowerCase()) === 0
                  ? n
                  : 0
                const head = Fmt.escapeHtml(modelData.substring(0, matched))
                const tail = Fmt.escapeHtml(modelData.substring(matched))
                return matched > 0
                  ? head + "<b>" + tail + "</b>"
                  : head + tail
              }
              textFormat: Text.RichText
              color: root.foreground
              font.family: root.textFontFamily
              font.pixelSize: Style.space(15)
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              visible: root.service && root.service.trendingTerms && root.service.trendingTerms.indexOf(modelData) !== -1
              text: "Trending"
              textFormat: Text.PlainText
              color: root.xGray
              font.family: root.textFontFamily
              font.pixelSize: Style.font.subtitle
              font.weight: Font.Normal
              elide: Text.ElideRight
            }
          }
        }
      }
    }
  }
}
