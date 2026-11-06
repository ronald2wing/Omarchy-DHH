pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as QQC
import qs.Commons
import qs.Ui
import "../base"
import "../post"
import "../search"
import "../render"
import "../../model"
import "../../js/entries.mjs" as Entries
import "../../js/search-status.mjs" as SearchStatus

// The panel body: layout, keys, selection, notice, and the copy, render and open actions. Built by the
// KeyboardPanel on the first open. The root is the key catcher, so the host can hand it keyboard focus
// directly; Escape and Tab reach the host through closeRequested and tabRequested.
PanelKeyCatcher {
  id: root

  required property Dataset dataset
  required property History history
  required property RecentSearches recentSearches
  required property PostCount postCount
  required property AvatarCache avatars
  required property ImageFolder imageFolder
  required property bool opened

  readonly property string query: searchField.text
  readonly property bool hasQuery: resultsState.hasQuery
  // The keyboard/hover-selected result row.
  property int selectedIndex: 0
  // The short-lived message under the lists.
  property string notice: ""
  // Set when a dropdown row fills the field, so the suggestion dropdown stays
  // closed until the user types again.
  property bool suggestionsDismissed: false
  property bool unfollowDialogShown: false
  // Only for show: nothing is followed, and the state resets when the shell
  // restarts.
  property bool following: true

  // The content's natural height, read by the host to size the panel.
  implicitHeight: header.height + bodyColumn.implicitHeight + Style.spacing.lg * 2
  blocked: searchField.hasFocus

  QtObject {
    id: internal
    // Posts per feed draw, and the search's result cap: a 37signals nod.
    readonly property int pageSize: 37
    // The drawTag of the header's "Render a random post" draw (one entry).
    readonly property string renderRandomTag: "render"
    // How far the feed list reaches below the viewport's bottom edge.
    readonly property real feedBelowViewport: feedList.height - (bodyScroll.contentY + bodyScroll.height - bodyColumn.y - feedList.y)
  }

  function scheduleSearch() {
    root.selectedIndex = 0
    resultsState.schedule()
  }

  function moveSelection(delta) {
    if (resultsState.model.count === 0) return
    root.selectedIndex = Math.max(0, Math.min(resultsState.model.count - 1, root.selectedIndex + delta))
    root.scrollRowIntoView(root.selectedIndex)
  }

  // The list does not scroll itself, so keep the row visible by scrolling
  // the body, and clear of the header overlaying its top.
  function scrollRowIntoView(i) {
    const item = resultsList.cardAt(i)
    if (!item) return
    const top = item.mapToItem(bodyScroll, 0, 0).y
    if (top < header.height) bodyScroll.contentY += top - header.height
    else if (top + item.height > bodyScroll.height) bodyScroll.contentY += top + item.height - bodyScroll.height
  }

  function fillFieldWith(query) {
    root.suggestionsDismissed = true
    searchField.text = query
    root.scheduleSearch()
    searchField.focusEditor()
  }

  function copyEntry(entry) {
    Desktop.copyText(Entries.clipboardText(entry))
    root.history.remember(entry)
  }

  // Copying a result also makes its query a recent search.
  function copyResult(entry) {
    root.recentSearches.remember(root.query)
    root.copyEntry(entry)
  }

  function renderEntry(entry) {
    if (renderer.busy) return
    root.history.remember(entry)
    renderer.render(entry)
  }

  function renderRandomEntry() {
    if (!root.dataset.ready) { root.showNotice(SearchStatus.LOADING_TEXT); return }
    root.dataset.draw(1, [], internal.renderRandomTag)
  }

  function showNotice(message) {
    root.notice = message
    noticeTimer.restart()
  }

  // Release the field's focus so the focus-driven dropdowns close when any
  // other panel element is clicked. MouseAreas are not focusable, so without
  // this the field keeps focus and the dropdown blocks the view.
  function releaseSearchFocus() {
    resultsState.cancelRemember()
    searchField.blurEditor()
    root.forceActiveFocus()
  }

  onMoveRequested: (dx, dy) => { if (dy !== 0) root.moveSelection(dy) }
  onActivateRequested: {
    if (!root.hasQuery || resultsState.model.count === 0) return
    root.copyResult(resultsState.model.get(root.selectedIndex).entry)
    // Keyboard copies have no hover, so tell the card to show "Copied".
    resultsList.showCopiedAt(root.selectedIndex)
  }

  FeedState {
    id: feedState
    dataset: root.dataset
    history: root.history
    avatars: root.avatars
    pageSize: internal.pageSize
    active: root.opened && !root.hasQuery
    scrolling: bodyScroll.moving
    // Within 1.5 viewport heights of the end: a steady scroll covers half a
    // viewport before a page has fully landed, so the cushion is generous.
    nearEnd: internal.feedBelowViewport <= bodyScroll.height * 1.5
  }

  ResultsState {
    id: resultsState
    dataset: root.dataset
    recentSearches: root.recentSearches
    avatars: root.avatars
    pageSize: internal.pageSize
    query: root.query
    // Typing already reset the selection (scheduleSearch), but arrows or
    // hover may have moved it while the search ran: new rows start at the
    // top row again.
    onReplaced: root.selectedIndex = 0
  }

  ImageRenderer {
    id: renderer
    avatars: root.avatars
    imageFolder: root.imageFolder
  }

  Connections {
    target: root.dataset
    function onDrawn(entries, tag) {
      if (tag !== internal.renderRandomTag) return
      if (entries.length > 0) root.renderEntry(entries[0])
      else root.showNotice("No posts to render")
    }
  }

  Connections {
    target: renderer
    function onFailed(message) { root.showNotice(message) }
  }

  Timer {
    id: noticeTimer
    interval: 2000
    onTriggered: root.notice = ""
  }

  // Scoped to the header's request: a Behavior on contentY would also
  // animate the keyboard selection's incremental scrolls and user flicks.
  NumberAnimation {
    id: scrollToTopAnimation
    target: bodyScroll
    property: "contentY"
    to: 0
    duration: 200
    easing.type: Easing.OutCubic
  }

  // Opaque "Lights Out" backdrop over the panel's themed fill, rounded to the
  // panel's inner radius so it never pokes out of the corners.
  Rectangle {
    anchors.fill: parent
    radius: Math.max(0, Style.cornerRadius - Look.panelBorderWidth)
    color: Look.surface
  }

  ProfileHeader {
    id: header
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    scrollY: bodyScroll.contentY
    following: root.following
    postCount: root.postCount.count
    onCloseRequested: root.closeRequested()
    onRenderRandomRequested: root.renderRandomEntry()
    onSearchRequested: searchField.focusEditor()
    onUnfollowRequested: root.unfollowDialogShown = true
    onFollowRequested: root.following = true
    onScrollToTopRequested: {
      bodyScroll.cancelFlick()
      scrollToTopAnimation.restart()
    }
  }

  Flickable {
    id: bodyScroll
    anchors.fill: parent
    clip: true
    contentWidth: width
    contentHeight: root.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height
    onMovementStarted: scrollToTopAnimation.stop()
    QQC.ScrollBar.vertical: QQC.ScrollBar { policy: QQC.ScrollBar.AsNeeded }

    // Click-catcher under the whole scrollable content: clicks that fall
    // through the interactive children dismiss the search dropdowns.
    MouseArea {
      anchors.fill: parent
      onClicked: root.releaseSearchFocus()
    }

    Column {
      id: bodyColumn
      x: Style.spacing.lg
      y: header.height + Style.spacing.lg
      width: bodyScroll.width - Style.spacing.lg * 2
      spacing: Style.spacing.sm

      // Clearance above and below the search pill, as on x.com.
      Column {
        width: parent.width
        topPadding: Style.spacing.xs
        bottomPadding: Style.spacing.xs

        SearchField {
          id: searchField
          navigable: resultsState.model.count > 0
          onEdited: {
            root.suggestionsDismissed = false
            root.scheduleSearch()
          }
          onMoveRequested: (delta) => root.moveSelection(delta)
          onLeaveRequested: root.releaseSearchFocus()
          // Regaining focus with a query but no suggestions re-runs the
          // search, which also resets the selection. The suggestions are
          // empty while a search runs and whenever no indexed term completes
          // the query, so in practice it repeats a search that found no
          // completions.
          onHasFocusChanged: {
            if (searchField.hasFocus && root.hasQuery && resultsState.suggestions.length === 0) root.scheduleSearch()
          }
        }
      }

      RenderPreview {
        width: parent.width
        imagePath: renderer.imagePath
        onOpenFolderRequested: {
          Desktop.openPath(root.imageFolder.path)
          root.releaseSearchFocus()
        }
      }

      PanelPostList {
        id: feedList
        visible: !resultsState.shown && feedState.model.count > 0
        model: feedState.model
        onCopyRequested: (entry) => root.copyEntry(entry)
      }

      ResultsStatusLine {
        width: parent.width
        visible: resultsState.shown
        text: resultsState.statusText
        rowCount: resultsState.model.count
      }

      PanelPostList {
        id: resultsList
        visible: resultsState.shown && resultsState.model.count > 0
        model: resultsState.model
        selectedIndex: root.selectedIndex
        onCopyRequested: (entry) => root.copyResult(entry)
        onEntered: (index) => { root.selectedIndex = index }
      }

      XText {
        width: parent.width
        visible: root.notice !== ""
        text: root.notice
        color: Look.accent
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }
    }
  }

  UnfollowDialog {
    shown: root.unfollowDialogShown
    onConfirmed: {
      root.following = false
      root.unfollowDialogShown = false
    }
    onCanceled: root.unfollowDialogShown = false
  }

  RecentSearchesDropdown {
    field: searchField
    scrollY: bodyScroll.contentY
    queries: root.recentSearches.queries
    shown: searchField.hasFocus && !root.hasQuery && root.recentSearches.queries.length > 0
    onQuerySelected: (query) => root.fillFieldWith(query)
    onForgetRequested: (query) => root.recentSearches.forget(query)
    onClearRequested: root.recentSearches.clear()
  }

  SuggestionsDropdown {
    field: searchField
    scrollY: bodyScroll.contentY
    suggestions: resultsState.suggestions
    trendingTerms: root.dataset.trendingTerms
    query: root.query
    shown: searchField.hasFocus && root.hasQuery && !root.suggestionsDismissed
    onQuerySelected: (query) => {
      root.recentSearches.remember(query)
      root.fillFieldWith(query)
    }
    // "Search for" confirms the query as typed: the results are already up,
    // so it only records the search and puts the dropdown away.
    onQueryConfirmed: {
      root.recentSearches.remember(root.query)
      root.suggestionsDismissed = true
      root.releaseSearchFocus()
    }
  }

  // A PostList wired to the panel's actions. The body column is inset
  // Style.spacing.lg on each side and the cards run edge to edge, so the
  // list shifts left by that inset and widens by both.
  component PanelPostList: PostList {
    x: -Style.spacing.lg
    width: parent.width + 2 * Style.spacing.lg
    avatars: root.avatars
    renderingKey: renderer.renderingKey
    onRenderRequested: (entry) => root.renderEntry(entry)
    onOpenSourceRequested: (entry) => Desktop.openUrl(entry.source)
    onActionTaken: root.releaseSearchFocus()
  }
}
