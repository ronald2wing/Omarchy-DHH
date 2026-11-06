pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import "../base"
import "../../js/highlight.mjs" as Highlight

// The suggestions dropdown: completions of the typed query, Trending terms first.
DropdownFrame {
  id: dropdown

  required property var suggestions
  required property var trendingTerms
  required property string query

  signal querySelected(string query)
  // The "Search for" row confirms the query as typed.
  signal queryConfirmed()

  // x.com's `Search for "query"` row, shown when no indexed term completes
  // the query: plain text flush left (no magnifier), straight quotes, the
  // query verbatim and wrapping however long it is.
  Item {
    visible: dropdown.suggestions.length === 0
    width: parent.width
    height: Math.max(Style.space(32), searchForLabel.implicitHeight)

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: dropdown.queryConfirmed()
    }

    XText {
      id: searchForLabel
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: "Search for \"" + dropdown.query.trim() + "\""
      wrapMode: Text.Wrap
      font.pixelSize: Style.space(15)
    }
  }

  Repeater {
    model: dropdown.suggestions

    delegate: DropdownRow {
      id: row
      required property string modelData

      // The typed prefix stays regular; only the completion is bold.
      labelHtml: Highlight.completionHtml(row.modelData, dropdown.query)
      caption: dropdown.trendingTerms.includes(row.modelData) ? "Trending" : ""
      onClicked: dropdown.querySelected(row.modelData)
    }
  }
}
