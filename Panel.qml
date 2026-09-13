pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as QQC
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "components"
import "search.js" as Search
import "format.js" as Fmt

Panel {
  id: root
  moduleName: "dhh"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var service: null

  // Emitted after a keyboard copy so the selected result card can show its
  // transient "Copied" tooltip (hover-driven triggers handle it themselves).
  signal copyConfirmed(int index)

  property string query: ""
  property string statusMessage: ""
  property string toast: ""
  property string renderOutputPath: ""
  property string renderingEntryText: ""
  property string renderError: ""
  property bool renderTimedOut: false
  property bool rendering: false
  property bool renderOutputSeen: false
  property int selectedIndex: 0
  // Suppresses the suggestion dropdown after a row click re-focuses the field,
  // until the user edits the text again.
  property bool suggestionsDismissed: false
  property var suggestions: []
  property bool workerReady: false
  property bool workerInitSent: false
  property int workerInitRetries: 0

  // Result cap passed to the worker; _scan clamps it to 40 and a capped scan is
  // labeled "<maxResults>+ results" in the status line.
  readonly property int maxResults: 37
  readonly property string renderScriptPath: Search.fileUrlToPath(Qt.resolvedUrl("bin/omarchy-dhh-render"))

  readonly property var barOwner: hostWidget || root
  // Proportional sans for all readable text: X's default proportional sans,
  // approximated with Noto Sans.
  readonly property string textFontFamily: "Noto Sans"
  readonly property color foreground: Color.foreground
  readonly property real secondaryOpacity: 0.62
  readonly property var httpSchemeRe: /^https?:\/\//
  // Opacity the share icon drops to while its entry's render is in flight.
  readonly property real renderingIconOpacity: 0.4

  // X-brand accent pushed through the theme-aware chrome.
  readonly property color xAccent: "#1D9BF0"
  // x.com's per-action hover colors: repost green, like pink. Reply/views/
  // bookmark/share all hover the blue accent.
  readonly property color xRepostGreen: "#00BA7C"
  readonly property color xLikePink: "#F91880"

  // X dark-mode palette + action-icon size, kept in sync with the render
  // script's inline CSS (bin/omarchy-dhh-render): .handle/.count fill #71767B,
  // .quote-container border #2F3336, .post-body/.name text #E7E9EA.
  // Resting search ring matches X's muted #536471 (panel-only).
  // .action-icon is 18.75px square.
  readonly property color xGray: "#71767B"
  readonly property color xDivider: "#2F3336"
  readonly property color xText: "#E7E9EA"
  readonly property color xSearchRing: "#536471"
  // X's unfollow hover red, mirroring the "Unfollow" pill state on x.com.
  readonly property color xDanger: "#F4212E"
  readonly property real xActionIconSize: Style.spaceReal(18.75)

  readonly property string avatarSource: Qt.resolvedUrl("data/avatar-x.png")
  readonly property string defaultAvatarSource: Qt.resolvedUrl("data/avatar-default.png")
  readonly property string companyLogoSource: Qt.resolvedUrl("data/company-logo.png")
  readonly property string renderIconTooltip: "Render image"
  readonly property string grokIconSource: Qt.resolvedUrl("data/icon-grok.svg")
  readonly property string grokIconSourceHover: Qt.resolvedUrl("data/icon-grok-blue.svg")
  readonly property size grokIconSize: Qt.size(33, 32)
  // Negative overlap that nests the hover-disc buttons' discs (Grok+"...",
  // bookmark+share) into one cluster.
  readonly property real discOverlap: -Style.spaceReal(8)
  readonly property string dotsIconSource: Qt.resolvedUrl("data/icon-dots.svg")
  readonly property string dotsIconSourceHover: Qt.resolvedUrl("data/icon-dots-blue.svg")

  // X chrome icons (verified badge, back/grok/search): single-path SVGs with
  // solid X colors baked in (e.g. #1D9BF0 verified seal).
  readonly property string verifiedBadgeSource: Qt.resolvedUrl("data/icon-verified.svg")
  // Context-author seal variants: organization is gold, government is grey.
  // Individual (or absent verified_type) and DHH's own badge stay blue.
  readonly property string verifiedBadgeGoldSource: Qt.resolvedUrl("data/icon-verified-gold.svg")
  readonly property string verifiedBadgeGreySource: Qt.resolvedUrl("data/icon-verified-grey.svg")
  readonly property string backIconSource: Qt.resolvedUrl("data/icon-back.svg")
  readonly property string grokIconSourceHeader: Qt.resolvedUrl("data/icon-grok-light.svg")
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
  readonly property string repostIconSourceHover: Qt.resolvedUrl("data/icon-repost-green.svg")
  readonly property string likeIconSourceHover: Qt.resolvedUrl("data/icon-like-pink.svg")
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

  // Card typography mirroring x.com's post text: 15px body/name/handle with a
  // 20px line height, matching the render script's 15px `.name`/`.handle`/
  // `.post-body`/`.quote-*` (the render already matches). The repost header
  // label is 13px, matching the render's `.count` scale.
  readonly property int cardTextSize: 15
  readonly property int cardLineHeight: 20
  readonly property int repostLabelSize: 13

  // contentY below which the header counts as "at the top" and shows its
  // expanded/icon state. A small epsilon (instead of an exact `=== 0`) lets
  // the header revert the moment the list is essentially at the top, without
  // waiting for the Flickable's momentum to decay to an exact zero offset.
  readonly property int headerCollapseThreshold: Style.space(16)

  // Total scrollable content height: the sticky header plus the body column
  // plus the top/bottom gutter. Shared by the keyboard panel's fitted height
  // and the body Flickable's contentHeight so they can't drift apart.
  readonly property real contentTotalHeight: headerBar.height + bodyColumn.implicitHeight + Style.spacing.lg * 2

  readonly property string displayName: "DHH"

  function open() {
    if (root.service) root.service.ensureDatasetLoaded()
    if (root.service) root.service.fetchPostCount()
    if (root.service) root.service.fetchAvatars(root.avatarHandlesFor(root.service.history))
    controller.show()
  }

  function close() { controller.hide() }

  onOpenedChanged: {
    if (!root.opened && root.service) root.service.cancelAvatarFetch()
  }
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

  function scheduleSearch() {
    root.selectedIndex = 0
    searchTimer.restart()
    recordTimer.restart()
  }

  // Reorder a suggestion list so trending terms lead (in trending order),
  // followed by the remaining terms in their original worker order.
  function prioritizeTrendingSuggestions(list) {
    const terms = root.service && root.service.trendingTerms ? root.service.trendingTerms : []
    if (terms.length === 0 || !list) return list || []
    const trending = terms.filter(t => list.includes(t))
    return trending.concat(list.filter(w => !trending.includes(w)))
  }

  // Resolve a context author's avatar from the Service cache; "" when uncached
  // (CircularAvatar then falls back to the bundled default).
  function contextAvatarSource(handle) {
    return root.service ? root.service.avatarFor(handle) : ""
  }

  // Collect the context handles worth prefetching avatars for: take each
  // entry's context handle raw. Service.fetchAvatars normalizes (strips one
  // leading @), validates against the helper's pattern, and dedupes.
  function avatarHandlesFor(entries) {
    return Array.isArray(entries) ? entries.map(e => Search.contextHandleOf(e)) : []
  }

  function runSearch() {
    resultModel.clear()
    root.suggestions = []
    if (root.query.trim() === "") { root.statusMessage = ""; return }
    // Connections may miss datasetLoadedChanged if service loads before
    // Panel receives the injection; retry the init handshake here so the
    // user never sees a perpetual "Loading dataset…".
    if (!root.workerReady) root.ensureWorkerInit()
    if (!root.workerReady) {
      root.statusMessage = "Loading dataset…"
      return
    }
    root.statusMessage = "Searching…"
    searchWorker.sendMessage({ type: "search", query: root.query, maxResults: root.maxResults })
  }

  function ensureWorkerInit() {
    if (root.workerReady || root.workerInitSent) return
    if (!root.service || !root.service.datasetLoaded) return
    root.workerInitSent = true
    initWatchdog.restart()
    const raw = root.service.datasetRaw || ""
    // WorkerScript silently drops string payloads above 16 MiB (2^24 bytes),
    // but `raw.length` counts UTF-16 code units, not bytes (each unit is up to
    // 3 UTF-8 bytes). Cap at 4 Mi code units (<=12 MiB) so a chunk can never
    // reach the transport limit; split only on line boundaries.
    const maxChunk = 4 * 1024 * 1024
    if (raw.length <= maxChunk) {
      searchWorker.sendMessage({ type: "init", raw: raw, done: true })
      return
    }
    let start = 0
    while (start < raw.length) {
      let end = Math.min(start + maxChunk, raw.length)
      if (end < raw.length) {
        const nl = raw.lastIndexOf("\n", end)
        if (nl > start) end = nl + 1
      }
      searchWorker.sendMessage({ type: "init", raw: raw.slice(start, end), done: end >= raw.length })
      start = end
    }
  }

  function updateResultStatus(count, capped) {
    if (capped) root.statusMessage = root.maxResults + "+ results"
    else if (count > 0) root.statusMessage = count + " result" + (count === 1 ? "" : "s")
    else root.statusMessage = "No matches for: " + root.query
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

  function copyEntry(entry) {
    const context = entry.context || {}
    // A bare repost (kind repost without context text) holds the other person's
    // words in `text`, so credit the context author; other entries are DHH's.
    const bareRepost = entry.kind === "repost" && !context.text
    const attribution = bareRepost && context.author && context.handle
      ? "— " + context.author + " (" + context.handle + ")"
      : "— David Heinemeier Hansson (@dhh)"
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
      parts.push("\n" + attribution)
    } else {
      const body = Search.stripLeadingMentions(entry.text, Search.contextHandleOf(entry))
      parts.push((body || "") + "\n\n" + attribution)
      if (url) parts.push(url)
    }

    Quickshell.clipboardText = parts.join("\n")
    if (root.service) root.service.rememberEntry(entry)
  }

  function entryAt(index) {
    if (index < 0 || index >= resultModel.count) return null
    return resultModel.get(index).entry
  }

  function copyEntryAt(index) {
    const entry = root.entryAt(index)
    if (entry) root.copyEntry(entry)
  }

  function renderEntry(entry) {
    // One render at a time: ignore clicks while a render is in flight.
    if (root.rendering) return
    const payload = JSON.stringify(entry)
    // Refuse entries whose serialized form would overflow a single argv
    // argument (Linux caps one argument at ~128 KiB), rather than let exec()
    // fail silently.
    if (Fmt.utf8ByteLength(payload) > 100 * 1024) {
      root.showToast("Entry too large to render")
      return
    }
    root.rendering = true
    root.renderOutputSeen = false
    if (root.service) root.service.rememberEntry(entry)
    root.renderingEntryText = entry.text
    root.renderError = ""
    root.renderTimedOut = false
    renderProcess.exec([root.renderScriptPath, payload])
    renderWatchdog.restart()
  }

  function renderEntryAt(index) {
    const entry = root.entryAt(index)
    if (entry) root.renderEntry(entry)
  }

  // Render a random entry as a shareable image (records history like any other
  // render). The random pick happens in the worker, so this just asks for one
  // once the dataset is loaded and the worker is ready.
  function renderRandomEntry() {
    if (!root.workerReady) root.ensureWorkerInit()
    if (!root.service || !root.service.datasetLoaded || !root.workerReady) {
      root.statusMessage = "Loading dataset…"
      return
    }
    searchWorker.sendMessage({ type: "random" })
  }

  // Open the entry's source URL in the default browser (the "..." / more
  // action on each result row). Same detached-exec pattern as openRenderOutputFolder.
  function openEntrySource(entry) {
    if (!entry || !entry.source) return
    // Only open http(s) URLs — never file://, magnet:, or other URI schemes.
    if (!root.httpSchemeRe.test(entry.source || "")) return
    Quickshell.execDetached(["xdg-open", entry.source])
  }

  function showToast(msg) {
    root.toast = msg
    toastTimer.restart()
  }

  function openRenderOutputFolder() {
    if (root.renderOutputPath === "") return
    const slash = root.renderOutputPath.lastIndexOf("/")
    if (slash < 1) return
    Quickshell.execDetached(["xdg-open", root.renderOutputPath.substring(0, slash)])
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
    onTriggered: { if (root.service) root.service.rememberSearch(root.query.trim()) }
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
  // this message with the generic "Render failed". The Quickshell Process type
  // exposes only signal(int), no group kill, so group termination
  // and KILL escalation live in the Ruby helper; this timer is the UI-side
  // backstop that escalates to SIGKILL if SIGTERM is ignored.
  Timer {
    id: renderWatchdog
    interval: 15000
    repeat: false
    onTriggered: {
      root.renderTimedOut = true
      root.rendering = false
      root.renderingEntryText = ""
      root.showToast("Render timed out")
      if (renderProcess.running) renderProcess.signal(15)
      renderKillWatchdog.restart()
    }
  }

  Timer {
    id: renderKillWatchdog
    interval: 3000
    repeat: false
    onTriggered: { if (renderProcess.running) renderProcess.signal(9) }
  }

  // Self-heal: if the init handshake stalls (a chunk dropped, worker never
  // acks), retry the send. Bounded by workerInitRetries so a permanently broken
  // worker cannot loop forever.
  Timer {
    id: initWatchdog
    interval: 8000
    repeat: false
    onTriggered: {
      if (root.workerReady || root.workerInitRetries >= 3) return
      root.workerInitRetries++
      root.workerInitSent = false
      root.ensureWorkerInit()
    }
  }

  WorkerScript {
    id: searchWorker
    source: "SearchWorker.js"
    onMessage: (msg) => {
      if (msg.type === "init") {
        root.workerReady = true
        initWatchdog.stop()
        // Release the retained dataset now that the worker holds its own copy.
        if (root.service) root.service.datasetRaw = ""
        return
      }
      if (msg.type === "trending") {
        if (root.service) root.service.trendingTerms = msg.trendingTerms || []
        return
      }
      if (msg.type === "random") {
        if (msg.entry) root.renderEntry(msg.entry)
        else root.showToast("No entries")
        return
      }
      if (msg.query !== root.query) return
      const hits = msg.results || []
      // Build all rows in one array and append them in a single ListModel call,
      // so the non-virtualized list re-layouts once instead of once per row
      // (clear + ~40 sequential appends). Each row carries the worker's
      // canonical picked entry (Search.pickEntry's shape) plus the precomputed
      // highlighted body, so the delegate never rebuilds the entry shape.
      const items = []
      hits.forEach(hit => {
        items.push({
          entry: hit,
          textHtml: Fmt.highlightHtml(Search.stripLeadingMentions(hit.text, Search.contextHandleOf(hit)), root.query)
        })
      })
      resultModel.append(items)
      if (root.service) root.service.fetchAvatars(root.avatarHandlesFor(hits))
      root.updateResultStatus(typeof msg.total === "number" ? msg.total : hits.length, !!msg.capped)
      root.selectedIndex = 0
      // Populate suggestions after the list settles so the dropdown opens only
      // once the result rows are in place.
      root.suggestions = root.prioritizeTrendingSuggestions(msg.suggestions || [])
    }
  }

  Connections {
    target: root.service
    // No `enabled` guard — if service is loaded before the Panel gets it
    // injected, datasetLoadedChanged fires while the Connections is still
    // disabled and ensureWorkerInit is missed, leaving workerReady=false
    // permanently and a stale worker state that segfaults on the first real
    // search message.
    function onDatasetLoadedChanged() {
      if (root.service && root.service.datasetLoaded) root.ensureWorkerInit()
    }
  }

  Process {
    id: renderProcess
    stdout: SplitParser {
      onRead: (line) => {
        root.renderOutputSeen = true
        root.renderOutputPath = line
      }
    }
    // Exit and stream-finished have no guaranteed order. A failed exit posts a
    // generic message; when the collector lands, replace it with the specific
    // stderr. A successful render may still log a clipboard-copy warning, but
    // by then the stdout reader has set renderOutputSeen, so the warning is
    // not surfaced.
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.renderError = String(text || "").trim()
        if (root.renderError !== "" && !root.renderOutputSeen) {
          root.showToast(root.renderError)
        }
      }
    }
    onExited: (exitCode) => {
      renderWatchdog.stop()
      renderKillWatchdog.stop()
      root.renderingEntryText = ""
      root.rendering = false
      if (exitCode !== 0 && !root.renderTimedOut) {
        const err = root.renderError !== "" ? root.renderError : "Render failed"
        root.showToast(err)
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
        root.service.rememberSearch(root.query.trim())
        root.copyEntryAt(root.selectedIndex)
        // Keyboard copy has no hover, so tell the selected card to surface its
        // "Copied" tooltip. A signal (not itemAtIndex) keeps the delegate's
        // custom member out of a dynamic QQuickItem lookup.
        root.copyConfirmed(root.selectedIndex)
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
        // Bar padding trimmed from lg+sm (12) to sm+sm (8) so the taller
        // identity row still lands the bar near x.com's ~53px compact header.
        height: headerLayout.height + Style.spacing.sm + Style.spacing.sm + 1
        // Overlay above bodyScroll: content scrolls up beneath this strip.
        z: 1

        // Semi-transparent dark backdrop for the scrolled header, matching
        // x.com's frosted profile strip. A fixed dark overlay reads
        // consistently on every theme; alpha-blending the themed foreground
        // would invert the tint on dark themes.
        Rectangle {
          anchors.fill: parent
          color: Util.alpha("#000000", 0.45)
          opacity: bodyScroll.contentY >= root.headerCollapseThreshold ? 1 : 0
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
          // 46px clears the 20px name + 15px subtitle identity column without
          // clipping (44px was exactly tight).
          height: Style.space(46)

          // Back arrow: closes the popup (same path as the Esc handler).
          HeaderIconButton {
            source: root.backIconSource
            tooltip: "Close"
            panelForeground: root.xText
            barForeground: root.barForeground
            accentColor: root.xAccent
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
                text: root.displayName
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.textFontFamily
                font.pixelSize: 20
                font.weight: Font.ExtraBold
                elide: Text.ElideRight
              }

              VerifiedBadge {
                size: Style.space(20)
                badgeSource: root.verifiedBadgeSource
                logoSource: root.companyLogoSource
                borderColor: root.xGray
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Text {
              width: parent.width
              text: root.service ? root.service.postCount : ""
              textFormat: Text.PlainText
              color: root.xGray
              font.family: root.textFontFamily
              font.pixelSize: 13
              elide: Text.ElideRight
            }
          }

          // Grok button: renders a random entry as a shareable image. Hidden
          // on scroll, where x.com swaps the action icons for the Following pill.
          HeaderIconButton {
            source: root.grokIconSourceHeader
            sourceSize: root.grokIconSize
            tooltip: "Render random entry"
            panelForeground: root.xText
            barForeground: root.barForeground
            accentColor: root.xAccent
            visible: bodyScroll.contentY < root.headerCollapseThreshold
            onClicked: root.renderRandomEntry()
          }

          // Search button: focuses the search field (opens the focus-triggered
          // recent-search dropdown). Hidden on scroll alongside the Grok button.
          HeaderIconButton {
            source: root.searchIconSource
            tooltip: "Search"
            panelForeground: root.xText
            barForeground: root.barForeground
            accentColor: root.xAccent
            visible: bodyScroll.contentY < root.headerCollapseThreshold
            onClicked: searchField.forceActiveFocus()
          }

          // x.com "Following" pill, shown only once content has scrolled beneath
          // the header (mirroring the real scrolled profile header). Tapping it
          // returns the body to the top.
          Rectangle {
            visible: bodyScroll.contentY >= root.headerCollapseThreshold
            Layout.alignment: Qt.AlignVCenter
            height: 36
            width: followingLabel.implicitWidth + Style.space(32)
            radius: height / 2
            color: "transparent"
            border.width: 1
            border.color: followPillMouse.containsMouse ? root.xDanger : root.xGray

            MouseArea {
              id: followPillMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                // Cancel an in-flight flick so the animation isn't fighting
                // momentum, then restart from the current offset.
                bodyScroll.cancelFlick()
                topScrollAnimation.stop()
                topScrollAnimation.start()
              }
            }

            // Scoped to the pill: a global Behavior on contentY would also
            // animate moveSelection()'s incremental writes and user flicks.
            NumberAnimation {
              id: topScrollAnimation
              target: bodyScroll
              property: "contentY"
              to: 0
              duration: 200
              easing.type: Easing.OutCubic
            }

            Text {
              id: followingLabel
              anchors.centerIn: parent
              text: followPillMouse.containsMouse ? "Unfollow" : "Following"
              textFormat: Text.PlainText
              color: followPillMouse.containsMouse ? root.xDanger : root.xText
              font.family: root.textFontFamily
              font.pixelSize: 15
              font.weight: Font.DemiBold
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
        // A user drag takes over from the pill's top-scroll animation.
        onMovementStarted: topScrollAnimation.stop()
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
                border.color: searchField.activeFocus ? root.xAccent : root.xSearchRing
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
              // textEdited fires only for user input, so the programmatic
              // assignment on a dropdown-row click leaves the dismissal flag set.
              onTextEdited: root.suggestionsDismissed = false
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
                opacity: root.secondaryOpacity
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
            visible: root.renderOutputPath !== ""
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
                root.openRenderOutputFolder()
                root.dismissSearch()
              }

              Image {
                id: renderPreview
                width: parent.width
                source: Util.fileUrl(root.renderOutputPath)
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
                opacity: root.secondaryOpacity
                font.family: root.textFontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }

              // Folder icon button: flat muted gray icon with a 28px hit
              // target, matching the PostCard action buttons.
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
                    root.openRenderOutputFolder()
                    root.dismissSearch()
                  }
                }

                AccentToolTip {
                  visible: folderBtnMouse.containsMouse
                  text: "Open folder"
                  panelForeground: root.xText
                  barForeground: root.barForeground
                  accentColor: root.xAccent
                }
              }
            }
          }

          FullBleed {
            fullWidth: bodyScroll.width
            visible: root.query.trim() === "" && root.service && root.service.history.length > 0
            spacing: Style.spacing.xxs

            HairlineDivider { color: root.xDivider }

            // History list. Eager Repeater (not a ListView): the outer
            // bodyScroll Flickable handles scrolling, so a ListView would add
            // unused scroll machinery for zero benefit. Most-recent-first order.
            Repeater {
              model: root.query.trim() === "" ? (root.service && root.service.history ? root.service.history : []) : []

              delegate: PostCard {
                required property var modelData
                required property int index

                panel: root
                entry: modelData
                textHtml: Fmt.highlightHtml(Search.stripLeadingMentions(modelData.text, Search.contextHandleOf(modelData)), "")
                selectOnHover: false
                selected: false
                cardWidth: bodyScroll.width
                renderBusy: root.renderingEntryText !== "" && modelData && modelData.text === root.renderingEntryText
                showDivider: index < root.service.history.length - 1

                onCopyRequested: root.copyEntry(modelData)
                onRenderRequested: root.renderEntry(modelData)
                onSourceRequested: root.openEntrySource(modelData)
                onDismissRequested: root.dismissSearch()
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
              text: root.statusMessage
              textFormat: Text.PlainText
              color: root.foreground
              opacity: root.secondaryOpacity
              font.family: root.textFontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }

            Item {
              width: Math.max(0, parent.width - (statusLabel.visible ? statusLabel.width : 0) - keyboardHint.implicitWidth - (statusLabel.visible ? 2 : 1) * Style.spacing.sm)
              height: 1
            }

            Text {
              id: keyboardHint
              text: resultModel.count > 0 ? "↑ ↓ navigate · Enter copy" : ""
              textFormat: Text.PlainText
              color: root.foreground
              opacity: root.secondaryOpacity
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
              text: root.statusMessage
              textFormat: Text.PlainText
              color: root.foreground
              opacity: root.secondaryOpacity
              font.family: root.textFontFamily
              font.pixelSize: Style.font.body
            }
          }

          FullBleed {
            fullWidth: bodyScroll.width
            visible: root.query.trim() !== "" && resultModel.count > 0
            HairlineDivider { color: root.xDivider }
          }

          FullBleed {
            fullWidth: bodyScroll.width
            visible: root.query.trim() !== "" && resultModel.count > 0
            ListView {
              id: resultScroll
              width: parent.width
              height: Math.max(Style.space(96), contentHeight)
              clip: true
              model: resultModel
              spacing: 0
              boundsBehavior: Flickable.StopAtBounds

              delegate: PostCard {
                // `entry` and `textHtml` are PostCard's own required properties,
                // auto-filled from the same-named model roles — no per-role
                // rebuild here.
                required property int index

                panel: root
                cardIndex: index
                selected: root.selectedIndex === index
                cardWidth: bodyScroll.width
                renderBusy: root.renderingEntryText !== "" && entry && entry.text === root.renderingEntryText
                showDivider: index < resultModel.count - 1

                onCopyRequested: {
                  root.service.rememberSearch(root.query.trim())
                  root.copyEntryAt(index)
                }
                onRenderRequested: root.renderEntryAt(index)
                onSourceRequested: root.openEntrySource(entry)
                onSelectedRequested: (idx) => { root.selectedIndex = idx }
                onDismissRequested: root.dismissSearch()

                Connections {
                  target: root
                  function onCopyConfirmed(copiedIndex) {
                    if (copiedIndex === index) showCopied()
                  }
                }
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

  // Focus-triggered recent-search dropdown, matching x.com's search-history
  // surface.
  SearchDropdown {
    keyCatcher: keyCatcher
    field: searchField
    scrollSource: bodyScroll
    height: recentColumn.implicitHeight + Style.space(16) * 2
    shouldShow: searchField.activeFocus
      && root.query.trim() === ""
      && root.service
      && root.service.recentSearches.length > 0

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
              if (root.service) root.service.clearRecentSearches()
            }
          }
        }
      }

      Repeater {
        model: root.service ? root.service.recentSearches : []
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
              root.suggestionsDismissed = true
              searchField.text = modelData
              searchField.forceActiveFocus()
            }
          }

          // Magnifier icon.
          MagnifierIcon {
            source: root.searchIconSource
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
                if (root.service) root.service.forgetSearch(modelData)
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
    keyCatcher: keyCatcher
    field: searchField
    scrollSource: bodyScroll
    height: suggestionColumn.implicitHeight + Style.space(16) * 2
    shouldShow: searchField.activeFocus
      && root.query.trim() !== ""
      && root.suggestions.length > 0
      && !root.suggestionsDismissed

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
              root.suggestionsDismissed = true
              root.service.rememberSearch(modelData)
              if (searchField.text !== modelData) searchField.text = modelData
              root.suggestions = []
              searchField.forceActiveFocus()
            }
          }

          // Magnifier icon.
          MagnifierIcon {
            source: root.searchIconSource
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
              // remainder after a leading, case-insensitive prefix); the
              // matched prefix stays regular weight. Both
              // portions are escaped before wrapping.
              text: {
                const q = root.query.trim()
                const n = q.length
                const matched = n > 0 && modelData.toLowerCase().startsWith(q.toLowerCase())
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
              visible: root.service && root.service.trendingTerms && root.service.trendingTerms.includes(modelData)
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
