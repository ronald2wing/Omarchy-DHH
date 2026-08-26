import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

// DHH glyph in the bar. Service.qml stays mounted with the bar so the dataset
// is ready when the panel opens. Click/IPC contract matches the Bible widget.
BarWidget {
  id: root
  moduleName: "dhh"

  Service {
    id: service
  }

  readonly property color barForeground: bar ? bar.barForeground : Color.foreground

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function injectPanel() {
    const target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("service" in target) target.service = service
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "dhh"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function togglePanel(): void { root.togglePanel() }
    function status(): string { return "DHH" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: "DHH quotes & X posts"
    foreground: root.barForeground
    iconComponent: Component {
      Image {
        anchors.centerIn: parent
        width: Style.font.body * 448 / 512
        height: Style.font.body
        source: Qt.resolvedUrl("data/icon-matrix.svg")
        sourceSize: Qt.size(24, 24)
        fillMode: Image.PreserveAspectFit
        smooth: true
      }
    }

    onPressed: (b) => {
      if (b === Qt.LeftButton) root.togglePanel()
    }
  }
}
