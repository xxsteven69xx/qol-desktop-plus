import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

Item {
  id: root
  required property var taskbar
  property bool opened: false
  property bool layoutSettled: false
  onOpenedChanged: {
    if (!opened) layoutSettled = false
    else refreshWallpaper()
  }
  property string wallpaperPath: ""
  function refreshWallpaper() { if (!wallpaperPathProcess.running) wallpaperPathProcess.running = true }
  // Read the same wallpaper link as Omarchy's desktop background service.
  // Resolve it again on open so theme and wallpaper changes follow automatically.
  Process {
    id: wallpaperPathProcess
    command: ["readlink", "-f", Quickshell.env("HOME") + "/.local/state/omarchy/current/background"]
    running: true
    stdout: StdioCollector { onStreamFinished: root.wallpaperPath = String(text || "").trim() }
  }
  Timer { interval: 2000; repeat: true; running: root.opened && root.option("showDesktop", true); onTriggered: root.refreshWallpaper() }
  property var items: []
  property int selectedIndex: 0
  readonly property var selected: items[selectedIndex] || null
  function option(name, fallback) { return taskbar.cfg("switcher", name, fallback) }
  function close() { opened = false }
  function advance(direction) {
    if (!option("enabled", true)) return
    if (!opened) {
      taskbar.settingsView.opened = false
      taskbar.close()
      var candidates = taskbar.snapshot.windows.filter(w =>
        (option("scope", "all") === "all" || w.workspace === taskbar.workspace || w.minimized)
        && (option("includeMinimized", true) || !w.minimized)
        && taskbar.cfg("bar", "excludedApps", []).indexOf(w.app) === -1)
      if (option("order", "recent") === "recent") candidates.sort((a,b) => a.focusHistory - b.focusHistory)
      items = candidates
      if (!items.length) return
      selectedIndex = Math.max(0, items.findIndex(w => w.active))
      opened = true
      Qt.callLater(() => { if (root.opened) { root.layoutSettled = true; keys.forceActiveFocus() } })
    }
    selectedIndex = (selectedIndex + direction + items.length) % items.length
  }
  function commit() {
    if (!opened) return
    var window = selected ? taskbar.windowFor(selected.address) : null
    close()
    if (!window) return
    var behavior = option("otherWorkspace", "switch")
    if (behavior === "taskbar") behavior = taskbar.cfg("windows", "otherWorkspace", "bring")
    var go = window.minimized ? taskbar.cfg("windows", "minimizedRestore", "current") === "original" : behavior === "switch"
    // Selecting an already focused window must never minimize it.
    taskbar.run(go ? "goto" : "restore", window.address)
  }
  Connections {
    target: root.taskbar
    function onSnapshotChanged() {
      if (!root.opened) return
      if (!root.option("enabled", true)) { root.close(); return }
      var address = root.selected?.address
      var remaining = root.items.filter(w => root.taskbar.windowFor(w.address) !== null)
      // Keep delegates and their animations alive across focus/title updates.
      if (remaining.length !== root.items.length) root.items = remaining
      if (!root.items.length) root.close()
      else root.selectedIndex = Math.max(0, root.items.findIndex(w => w.address === address))
    }
  }
  // Catch quick Alt+Tab taps whose Alt release precedes the overlay mapping.
  Timer { id: altPoll; interval: 100; repeat: true; running: root.opened && root.option("releaseAltToSelect", true); onTriggered: if (!altState.running) altState.running = true }
  Process {
    id: altState
    command: ["hyprctl", "repl", "hl.is_key_down('Alt_L') or hl.is_key_down('Alt_R')"]
    stdout: SplitParser { onRead: data => { if (data.trim() === "false" && root.opened && root.option("releaseAltToSelect", true)) root.commit() } }
  }

  PanelWindow {
    id: panel
    screen: root.taskbar.surface?.screen || null
    visible: root.opened
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-taskbar-switcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Rectangle {
      anchors.fill: parent
      visible: root.option("showDesktop", true)
      color: Color.background
      Image {
        anchors.fill: parent
        source: root.wallpaperPath ? Util.fileUrl(root.wallpaperPath) : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
      }
    }
    Rectangle { anchors.fill: parent; color: Color.imagePicker.scrim }
    MouseArea { anchors.fill: parent; onClicked: root.close() }
    Item {
      id: keys
      anchors.fill: parent
      focus: true
      readonly property real maxPreviewWidth: Math.min(width - 80, root.option("width", 768))
      readonly property real maxPreviewHeight: Math.min(height * .65, root.option("height", 475))
      readonly property var selectedWindow: root.taskbar.windowFor(root.selected?.address) || root.selected
      readonly property var windowSize: selectedWindow?.size || [maxPreviewWidth, maxPreviewHeight]
      readonly property real aspect: windowSize[0] > 0 && windowSize[1] > 0 ? windowSize[0]/windowSize[1] : maxPreviewWidth/maxPreviewHeight
      readonly property real expandedWidth: root.option("adaptiveSize", true) ? Math.min(maxPreviewWidth, maxPreviewHeight*aspect) : maxPreviewWidth
      readonly property real expandedHeight: root.option("adaptiveSize", true) ? Math.min(maxPreviewHeight, maxPreviewWidth/aspect) : maxPreviewHeight
      readonly property real sliceWidth: root.option("sliceWidth", 108)
      readonly property real skew: root.option("skewOffset", 28)
      readonly property real previewX: (width - expandedWidth)/2
      readonly property real previewY: (height - maxPreviewHeight - Style.space(44))/2
      readonly property int motionDuration: root.option("animationDurationMs", 220)
      readonly property real gap: root.option("spacing", 12)
      function backgroundSize(index) {
        var window = root.taskbar.windowFor(root.items[index]?.address) || root.items[index]
        var size = window?.size || [maxPreviewWidth, maxPreviewHeight]
        var ratio = size[0] > 0 && size[1] > 0 ? size[0]/size[1] : maxPreviewWidth/maxPreviewHeight
        var scale = root.option("backgroundScale", 0.9)
        return Qt.size(Math.min(maxPreviewWidth, maxPreviewHeight*ratio)*scale,
                       Math.min(maxPreviewHeight, maxPreviewWidth/ratio)*scale)
      }
      function backgroundStep(index) {
        var w = backgroundSize(index).width
        return Math.min(w, Math.max(sliceWidth, w*root.option("backgroundReveal", 0.62))) + gap
      }
      function cardX(index) {
        if (index === root.selectedIndex) return previewX
        var offset = 0
        if (index < root.selectedIndex) {
          for (var i=index; i<root.selectedIndex; i++) offset += backgroundStep(i)
          return previewX - offset
        }
        for (var i=root.selectedIndex+1; i<=index; i++) offset += backgroundStep(i)
        return previewX + expandedWidth + offset - backgroundSize(index).width
      }
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) root.close()
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) root.commit()
        else if (event.key === Qt.Key_Left || event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && event.modifiers & Qt.ShiftModifier)) root.advance(-1)
        else if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab) root.advance(1)
        else return
        event.accepted = true
      }
      Keys.onReleased: event => {
        if (event.key === Qt.Key_Alt && root.option("releaseAltToSelect", true)) { root.commit(); event.accepted = true }
      }
      Repeater {
        id: cards
        // An integer model preserves delegates when a snapshot object changes.
        model: root.items.length
        Item {
          id: card
          required property int index
          readonly property var modelData: root.taskbar.windowFor(root.items[index]?.address) || root.items[index]
          readonly property bool selected: index === root.selectedIndex
          readonly property int distance: index - root.selectedIndex
          visible: Math.abs(distance) <= root.option("neighbors", 3)
          z: selected ? 100 : 50 - Math.min(Math.abs(distance), 40)
          readonly property size backgroundSize: keys.backgroundSize(index)
          width: selected ? keys.expandedWidth : backgroundSize.width
          height: selected ? keys.expandedHeight : backgroundSize.height
          x: keys.cardX(index)
          y: keys.previewY + (keys.maxPreviewHeight - height)/2
          readonly property real skew: selected ? 0 : Math.min(Math.abs(keys.skew), width/2)
          readonly property real corner: selected ? Math.min(root.option("selectedCornerRadius", 0), width/2, height/2) : 0
          readonly property real topLeft: keys.skew >= 0 ? skew : 0
          readonly property real topRight: keys.skew >= 0 ? width : width-skew
          readonly property real bottomRight: keys.skew >= 0 ? width-skew : width
          readonly property real bottomLeft: keys.skew >= 0 ? 0 : skew
          Behavior on x { enabled: root.layoutSettled; NumberAnimation { duration: keys.motionDuration; easing.type: Easing.OutCubic } }
          Behavior on width { enabled: root.layoutSettled; NumberAnimation { duration: keys.motionDuration; easing.type: Easing.OutCubic } }
          Behavior on height { enabled: root.layoutSettled; NumberAnimation { duration: keys.motionDuration; easing.type: Easing.OutCubic } }
          Item {
            id: maskShape
            anchors.fill: parent
            visible: false
            layer.enabled: true
            Shape {
              anchors.fill: parent
              antialiasing: true
              preferredRendererType: Shape.CurveRenderer
              ShapePath {
                fillColor: "white"; strokeColor: "transparent"
                startX: card.topLeft + card.corner; startY: 0
                PathLine { x: card.topRight - card.corner; y: 0 }
                PathQuad { x: card.topRight; y: card.corner; controlX: card.topRight; controlY: 0 }
                PathLine { x: card.bottomRight; y: card.height - card.corner }
                PathQuad { x: card.bottomRight - card.corner; y: card.height; controlX: card.bottomRight; controlY: card.height }
                PathLine { x: card.bottomLeft + card.corner; y: card.height }
                PathQuad { x: card.bottomLeft; y: card.height - card.corner; controlX: card.bottomLeft; controlY: card.height }
                PathLine { x: card.topLeft; y: card.corner }
                PathQuad { x: card.topLeft + card.corner; y: 0; controlX: card.topLeft; controlY: 0 }
              }
            }
          }
          Item {
            anchors.fill: parent
            layer.enabled: true
            layer.smooth: true
            layer.effect: MultiEffect {
              maskEnabled: true
              maskSource: maskShape
              maskThresholdMin: 0.3
              maskSpreadAtMin: 0.3
            }
            Rectangle { anchors.fill: parent; color: Color.background }
            Item {
              anchors.fill: parent
              clip: true
              ScreencopyView {
                id: capture
                anchors.centerIn: parent
                // Fit the complete window in every card; neighboring cards overlap it.
                constraintSize: Qt.size(Math.max(1, card.width - 6), Math.max(1, card.height - 6))
                captureSource: root.opened && card.visible ? root.taskbar.toplevelFor(card.modelData.address) : null
                live: root.opened && card.selected && root.option("livePreview", true) && !card.modelData.minimized
                paintCursor: false
              }
              Image { anchors.centerIn: parent; width: Style.space(64); height: width; visible: !capture.hasContent; source: root.taskbar.iconFor(card.modelData.app) }
              Rectangle {
                anchors.fill: parent; color: Color.background; opacity: card.selected ? 0 : .42
                Behavior on opacity { enabled: root.layoutSettled; NumberAnimation { duration: keys.motionDuration; easing.type: Easing.OutCubic } }
              }
            }
          }
          Rectangle {
            anchors.fill: parent
            anchors.margins: 1.5
            visible: card.selected
            color: "transparent"
            radius: root.option("selectedCornerRadius", 0)
            border.color: Color.imagePicker.selectedBorder
            border.width: 3
          }
          Shape {
            visible: !card.selected
            anchors.fill: parent
            antialiasing: true
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
              fillColor: "transparent"
              strokeColor: card.selected ? Color.imagePicker.selectedBorder : Color.imagePicker.unselectedBorder
              strokeWidth: card.selected ? 3 : 1
              startX: card.topLeft; startY: 0
              PathLine { x: card.topRight; y: 0 }
              PathLine { x: card.bottomRight; y: card.height }
              PathLine { x: card.bottomLeft; y: card.height }
              PathLine { x: card.topLeft; y: 0 }
            }
          }
          MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { if (card.selected) root.commit(); else root.selectedIndex = card.index } }
        }
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: keys.previewY + keys.maxPreviewHeight + Style.space(16)
        width: Math.max(keys.expandedWidth, Math.min(360, keys.maxPreviewWidth))
        text: root.selected?.title || ""
        textFormat: Text.PlainText
        color: Color.imagePicker.text
        font.family: Style.font.family
        font.pixelSize: Style.font.display
        font.weight: Font.DemiBold
        maximumLineCount: 2
        wrapMode: Text.Wrap
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignHCenter
      }
    }
  }
}
