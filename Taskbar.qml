import QtQuick
import QtQuick.Controls as Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "qol-desktop-plus"
  MouseArea { anchors.fill: parent; acceptedButtons: Qt.RightButton; onClicked: root.openMenu("") }
  // Omarchy-style ModuleSlots overlay a drag handler for moving whole widgets.
  // This widget owns pointer gestures inside its window list. Raise only its
  // Loader above that overlay; the host bar does not need to be patched.
  Binding {
    target: root.parent
    property: "z"
    value: 1
    when: root.parent !== null && root.parent.parent !== null && root.parent.parent.activeItem === root
    restoreMode: Binding.RestoreBindingOrValue
  }
  IpcHandler {
    target: "qol-desktop-plus." + root.screenName
    function settings(): void { settingsPanel.open() }
    function switcher(direction: int): void { appSwitcher.advance(direction) }
    function activate(slot: int): bool {
      if (slot < 1 || slot > 10 || slot > root.entries.length) return false
      var entry = root.entries[slot - 1]
      // A grouped shortcut toggles its focused member, or its first window.
      var active = root.windows.find(w => w.app === entry.app && w.active)
      root.close()
      root.run("toggle", entry.count > 1 && active ? active.address : entry.address)
      return true
    }
  }
  AppSwitcher { id: appSwitcher; taskbar: root }
  property alias switcherView: appSwitcher
  SettingsPanel { id: settingsPanel; taskbar: root }
  property alias settingsView: settingsPanel
  property var snapshot: ({windows: [], monitors: [], modes: {}, preferences: {}})
  property string selectedAddress: ""
  property string groupFilter: ""
  property string popupMode: ""
  property string previewAddress: ""
  property Item previewAnchor: root
  readonly property bool previewReady: capture.hasContent
  property string pendingPreview: ""
  property bool iconHovered: false
  property string dragAddress: ""
  property string dragBefore: ""
  readonly property string helper: Qt.resolvedUrl("taskbar.py").toString().replace(/^file:\/\//, "")
  readonly property var surface: root.QsWindow.window
  readonly property string screenName: surface && surface.screen ? surface.screen.name : ""
  readonly property var monitor: (snapshot.monitors || []).find(m => m.name === screenName)
  readonly property string workspace: monitor ? monitor.activeWorkspace.name : (snapshot.workspace || "")
  readonly property bool floatingMode: (snapshot.modes || {})[workspace] ?? cfg("workspace", "defaultFloating", false)
  readonly property var preferences: ({groupApps:cfg("grouping", "enabled", false), restoreFullscreen:cfg("windows", "restoreFullscreen", false)})
  function cfg(section, key, fallback) { return snapshot.config?.[section]?.[key] ?? fallback }
  readonly property bool showLayout: cfg("bar", "showLayoutButton", true)
  readonly property real settingsExtent: Style.space(cfg("bar", "settingsAreaWidth", 24))
  readonly property real layoutExtent: showLayout ? cell + Style.space(7) : 0
  readonly property real iconSpacing: Style.space(cfg("bar", "spacing", 2))
  readonly property color foreground: bar ? bar.barForeground : Color.bar.text
  readonly property var windows: snapshot.windows.filter(w => (cfg("bar", "allWorkspaces", true) || w.workspace === workspace || w.minimized) && (!cfg("bar", "currentMonitorOnly", false) || w.monitor === monitor?.id) && cfg("bar", "excludedApps", []).indexOf(w.app) === -1)
  readonly property var entries: makeEntries()
  readonly property real cell: Style.space(cfg("bar", "cellSize", 30))
  readonly property int capacity: Math.max(1, Math.floor(Style.space(cfg("bar", "maxWidth", 260)) / (cell + iconSpacing)))
  readonly property bool overflow: entries.length > capacity
  readonly property var visibleEntries: entries.slice(0, overflow ? Math.max(1, capacity - 1) : capacity)
  readonly property var pickerWindows: windows.filter(w => !groupFilter || w.app === groupFilter)
  implicitWidth: vertical ? barSize : layoutExtent + visibleEntries.length * (cell + iconSpacing) + (overflow ? cell : 0) + settingsExtent
  implicitHeight: vertical ? cell * (visibleEntries.length + (showLayout ? 1 : 0) + (overflow ? 1 : 0)) + settingsExtent : barSize

  // Keep delegates alive when titles, focus, or other windows change.
  ListModel { id: taskModel }
  onVisibleEntriesChanged: syncEntries()
  Component.onCompleted: syncEntries()
  function syncEntries() {
    if (!taskModel) return
    var wanted = visibleEntries
    for (var i = 0; i < wanted.length; ++i) {
      var found = -1
      for (var j = i; j < taskModel.count; ++j) if (taskModel.get(j).address === wanted[i].address) { found = j; break }
      if (found < 0) taskModel.insert(i, wanted[i])
      else {
        if (found !== i) taskModel.move(found, i, 1)
        for (var name in wanted[i]) if (taskModel.get(i)[name] !== wanted[i][name]) taskModel.setProperty(i, name, wanted[i][name])
      }
    }
    if (taskModel.count > wanted.length) taskModel.remove(wanted.length, taskModel.count - wanted.length)
  }
  function makeEntries() {
    if (!preferences.groupApps) return windows.map(w => ({address:w.address, app:w.app, title:w.title, active:w.active, minimized:w.minimized, count:1}))
    var groups = []
    for (var w of windows) {
      var group = groups.find(g => g.app === w.app)
      if (!group) { group = {address:w.address, app:w.app, title:w.title, active:false, minimized:true, count:0}; groups.push(group) }
      group.count++; group.active = group.active || w.active; group.minimized = group.minimized && w.minimized
    }
    return groups
  }
  function windowFor(address) { return snapshot.windows.find(w => w.address === address) || null }
  function toplevelFor(address) {
    return Hyprland.toplevels.values.find(t => ("0x" + t.address.replace(/^0x/, "")) === address)?.wayland || null
  }
  function run(action, address, extra) {
    var options = Object.assign({screen:screenName, windowKey:windowFor(address)?.key || ""}, extra || {})
    Quickshell.execDetached(["python3", helper, action, address || "", JSON.stringify(options)])
  }
  function close() { popupMode = ""; previewAddress = ""; previewDelay.stop() }
  function choose(entry) {
    close()
    if (entry.count > 1 && cfg("grouping", "clickAction", "picker") === "picker") { groupFilter = entry.app; popupMode = "picker" }
    else { var active = windows.find(w => w.app === entry.app && w.active); run("toggle", entry.count > 1 && active ? active.address : entry.address) }
  }
  function openMenu(address) { close(); selectedAddress = address || ""; popupMode = "actions" }
  function iconFor(app) {
    var normalized = app.toLowerCase()
    var entry = DesktopEntries.applications.values.find(e => String(e.id).replace(/\.desktop$/, "").toLowerCase() === normalized || String(e.startupClass || "").toLowerCase() === normalized)
    return Quickshell.iconPath(entry ? entry.icon : app, true) || Quickshell.iconPath("application-x-executable", true)
  }
  function beginHover(address, item) {
    if (!cfg("preview", "enabled", true)) return
    iconHovered = true; pendingPreview = address; previewAnchor = item; previewDelay.restart(); previewHide.stop()
  }
  function endHover() { iconHovered = false; previewDelay.stop(); previewHide.restart() }
  function status(w) {
    if (!w) return ""
    return (w.minimized ? (cfg("windows", "minimizedRestore", "current") === "current" ? "Minimized · restore here" : "Minimized · restore to original workspace") : w.workspace !== workspace ? (cfg("windows", "otherWorkspace", "bring") === "switch" ? "Switch to workspace" : "Bring to this workspace") : w.active ? "Click to " + cfg("windows", "activeClick", "minimize") : "Click to focus") + " · workspace " + w.workspace
  }

  Process {
    id: watcher
    command: ["python3", root.helper, "watch"]
    running: true
    stdout: SplitParser { onRead: data => { try { root.snapshot = JSON.parse(data) } catch (e) { console.warn("Taskbar snapshot:", e) } } }
    stderr: SplitParser { onRead: data => console.warn("Taskbar:", data) }
    onExited: restart.restart()
  }
  Timer { id: restart; interval: 2000; onTriggered: watcher.running = true }
  Timer { id: previewDelay; interval: root.cfg("preview", "delayMs", 450); onTriggered: if (root.iconHovered && !root.popupMode && !root.dragAddress) root.previewAddress = root.pendingPreview }
  Timer { id: previewHide; interval: root.cfg("preview", "hideDelayMs", 250); onTriggered: if (!root.iconHovered && !preview.containsMouse) root.previewAddress = "" }

  Item {
    id: layoutButton
    visible: root.showLayout
    width: root.vertical ? root.barSize : root.cell
    height: root.vertical ? root.cell : root.barSize
    Text {
      anchors.centerIn: parent
      text: root.floatingMode ? "󰒄" : "󰕰"
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.body
      color: layoutMouse.containsMouse ? Color.accent : root.foreground
    }
    MouseArea {
      id: layoutMouse
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      cursorShape: Qt.PointingHandCursor
      onClicked: event => { if (event.button === Qt.RightButton) root.openMenu(""); else root.run("layout") }
      onEntered: if (root.bar && root.cfg("workspace", "showTooltip", true)) root.bar.showTooltip(layoutButton, root.floatingMode ? "Click to enable managed (tiled) windows" : "Click to enable floating windows")
      onExited: if (root.bar) root.bar.hideTooltip(layoutButton)
    }
  }
  Rectangle {
    visible: root.showLayout
    x: root.vertical ? Style.space(7) : root.cell + Style.space(2)
    y: root.vertical ? root.cell : (root.barSize - height) / 2
    width: root.vertical ? root.barSize - Style.space(14) : 1
    height: root.vertical ? 1 : Style.space(12)
    color: root.foreground; opacity: .22
  }
  Grid {
    id: tasks
    x: root.vertical ? 0 : root.layoutExtent
    y: root.vertical && root.showLayout ? root.cell : 0
    columns: root.vertical ? 1 : Math.max(1, root.visibleEntries.length + (root.overflow ? 1 : 0))
    spacing: root.iconSpacing
    Repeater {
      model: taskModel
      Rectangle {
        id: task
        required property var model
        readonly property var modelData: model
        readonly property string address: modelData.address
        width: root.vertical ? root.barSize : root.cell
        height: root.barSize
        radius: Math.min(Style.cornerRadius, Style.space(4))
        color: mouse.containsMouse || modelData.active ? Qt.alpha(root.foreground, modelData.active ? .1 : .06) : "transparent"
        border.width: root.dragBefore === address ? 1 : 0
        border.color: Color.accent
        opacity: root.dragAddress === address ? .45 : 1
        Behavior on color { ColorAnimation { duration: root.cfg("bar", "animationDurationMs", 140) } }
        Image { anchors.centerIn: parent; width: Style.space(root.cfg("bar", "iconSize", 17)); height: width; source: root.iconFor(task.modelData.app); fillMode: Image.PreserveAspectFit; opacity: task.modelData.minimized ? root.cfg("bar", "minimizedOpacity", .48) : 1 }
        Text {
          visible: root.cfg("bar", "showGroupCounts", true) && task.modelData.count > 1
          anchors.right: parent.right; anchors.top: parent.top
          text: task.modelData.count
          color: root.foreground
          font.family: Style.font.family; font.pixelSize: Style.font.caption; font.bold: true
        }
        Rectangle {
          visible: root.cfg("bar", "showIndicators", true)
          anchors.bottom: parent.bottom; anchors.bottomMargin: Style.space(2); anchors.horizontalCenter: parent.horizontalCenter
          width: task.modelData.active ? Style.space(14) : Style.space(5); height: Style.space(2)
          color: task.modelData.active ? Color.accent : root.foreground
          opacity: task.modelData.minimized ? .3 : .8
        }
        MouseArea {
          id: mouse
          anchors.fill: parent
          hoverEnabled: true
          acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
          cursorShape: pressed ? Qt.ClosedHandCursor : Qt.PointingHandCursor
          property real pressX: 0
          property real pressY: 0
          property bool moved: false
          onEntered: root.beginHover(task.address, task)
          onExited: root.endHover()
          onPressed: event => { pressX = event.x; pressY = event.y; moved = false }
          onPositionChanged: event => {
            if (!root.cfg("interaction", "dragToReorder", true) || !(pressedButtons & Qt.LeftButton)) return
            if (Math.abs(event.x - pressX) + Math.abs(event.y - pressY) < root.cfg("interaction", "dragThreshold", 6) && !moved) return
            moved = true; root.previewAddress = ""; root.dragAddress = task.address
            var point = task.mapToItem(tasks, event.x, event.y)
            var candidate = tasks.childAt(point.x, point.y)
            root.dragBefore = candidate && candidate.address ? candidate.address : ""
          }
          onReleased: {
            if (moved) root.run("reorder", task.address, {before:root.dragBefore})
            root.dragAddress = ""; root.dragBefore = ""
          }
          onCanceled: { root.dragAddress = ""; root.dragBefore = "" }
          onClicked: event => { if (!moved) { if (event.button === Qt.RightButton) root.openMenu(task.address); else if (event.button === Qt.MiddleButton) { var action = root.cfg("interaction", "middleClick", "none"); if (action !== "none") root.run(action, task.address) } else root.choose(task.modelData) } }
        }
      }
    }
    Item {
      visible: root.overflow
      width: visible ? root.cell : 0; height: root.barSize
      Text { anchors.centerIn: parent; text: "…"; color: root.foreground; font.pixelSize: Style.font.body }
      MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.close(); root.groupFilter = ""; root.popupMode = "picker" } }
    }
  }

  QtObject { id: previewOwner; function close() { root.previewAddress = "" } }
  PopupCard {
    id: preview
    anchorItem: root.previewAnchor || root
    bar: root.bar
    owner: previewOwner
    triggerMode: "hover"
    open: root.cfg("preview", "enabled", true) && root.previewAddress !== "" && root.windowFor(root.previewAddress) !== null && !root.popupMode
    contentWidth: fittedContentWidth(Style.space(root.cfg("preview", "width", 300)))
    contentHeight: fittedContentHeight(previewContent.implicitHeight)
    onContainsMouseChanged: if (!containsMouse) previewHide.restart()
    Column {
      id: previewContent
      width: parent.width
      spacing: Style.space(8)
      Item {
        visible: root.cfg("preview", "showImage", true)
        width: parent.width; height: Style.space(root.cfg("preview", "height", 145))
        ScreencopyView {
          id: capture
          anchors.centerIn: parent
          constraintSize: Qt.size(parent.width, parent.height)
          captureSource: preview.open ? root.toplevelFor(root.previewAddress) : null
          live: root.cfg("preview", "live", true) && preview.open && !(root.windowFor(root.previewAddress)?.minimized || false)
          paintCursor: false
        }
      }
      Text { visible: root.cfg("preview", "showTitle", true); width: parent.width; text: root.windowFor(root.previewAddress)?.title || ""; textFormat: Text.PlainText; maximumLineCount: root.cfg("preview", "titleLines", 2); wrapMode: Text.Wrap; elide: Text.ElideRight; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
    }
  }

  PopupCard {
    id: popup
    anchorItem: root; bar: root.bar; owner: root
    open: root.popupMode !== ""
    contentWidth: fittedContentWidth(Style.space(root.popupMode === "picker" ? root.cfg("picker", "width", 370) : 330))
    contentHeight: fittedContentHeight(root.popupMode === "picker" ? Math.min(Style.space(root.cfg("picker", "maxHeight", 420)), picker.contentHeight) : actions.implicitHeight)
    Controls.ScrollView {
      visible: root.popupMode === "picker"
      anchors.fill: parent
      clip: true
      ListView {
        id: picker
        model: root.pickerWindows
        spacing: Style.space(4)
        delegate: Rectangle {
          required property var modelData
          width: picker.width; height: Style.space(root.cfg("picker", "rowHeight", 54))
          color: pickerMouse.containsMouse ? Qt.alpha(root.foreground, .08) : "transparent"
          Row {
            anchors.fill: parent; anchors.margins: Style.space(6); spacing: Style.space(10)
            Image { width: Style.space(22); height: width; anchors.verticalCenter: parent.verticalCenter; source: root.iconFor(modelData.app); opacity: modelData.minimized ? .5 : 1 }
            Column {
              width: parent.width - Style.space(32); spacing: Style.space(3)
              Text { width: parent.width; text: modelData.title; textFormat: Text.PlainText; elide: Text.ElideRight; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
              Text { visible: root.cfg("picker", "showWorkspace", true); width: parent.width; text: root.status(modelData); elide: Text.ElideRight; color: root.foreground; opacity: .65; font.family: Style.font.family; font.pixelSize: Style.font.caption }
            }
          }
          MouseArea {
            id: pickerMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: event => { if (event.button === Qt.RightButton) root.openMenu(modelData.address); else { root.run("toggle", modelData.address); root.close() } }
          }
        }
      }
    }
    Column {
      id: actions
      visible: root.popupMode === "actions"
      width: parent.width; spacing: Style.space(4)
      Repeater {
        model: root.selectedAddress ? [{label:"Bring here", action:"restore"}, {label:"Go to window", action:"goto"}, {label:"Minimize", action:"minimize"}, {label:"Maximize / restore size", action:"maximize"}, {label:"Toggle fullscreen", action:"fullscreen"}, {label:"Close window", action:"close"}] : []
        Button { radius: 0; leftAlign: true; focusable: true; fontSize: Style.font.heading; required property var modelData; width: parent.width; text: modelData.label; foreground: root.foreground; onClicked: { root.run(modelData.action, root.selectedAddress); root.close() } }
      }
      Button { radius: 0; leftAlign: true; focusable: true; fontSize: Style.font.heading; visible: !root.selectedAddress; width: parent.width; text: root.floatingMode ? "Enable managed windows" : "Enable floating windows"; foreground: root.foreground; onClicked: { root.run("layout"); root.close() } }
      Button { radius: 0; leftAlign: true; focusable: true; fontSize: Style.font.heading; visible: !root.selectedAddress; width: parent.width; text: "Restore all minimized windows"; foreground: root.foreground; onClicked: { root.run("restore-all"); root.close() } }
      Button { radius: 0; leftAlign: true; focusable: true; fontSize: Style.font.heading; width: parent.width; text: (root.preferences.groupApps ? "✓ " : "") + "Group windows by app"; foreground: root.foreground; onClicked: { root.run("preferences", "", {groupApps:!root.preferences.groupApps}); root.close() } }
      Button { radius: 0; leftAlign: true; focusable: true; fontSize: Style.font.heading; width: parent.width; text: (root.preferences.restoreFullscreen ? "✓ " : "") + "Restore true fullscreen"; foreground: root.foreground; onClicked: { root.run("preferences", "", {restoreFullscreen:!root.preferences.restoreFullscreen}); root.close() } }
      Button { radius: 0; leftAlign: true; focusable: true; fontSize: Style.font.heading; width: parent.width; text: "All windows…"; foreground: root.foreground; onClicked: { root.groupFilter = ""; root.popupMode = "picker" } }
      Rectangle { width: parent.width; height: 1; color: root.foreground; opacity: .2 }
      Button { radius: 0; leftAlign: true; focusable: true; fontSize: Style.font.heading; objectName: "taskbarSettingsMenuEntry"; width: parent.width; text: "Taskbar settings…"; foreground: root.foreground; onClicked: settingsPanel.open() }
    }
  }
}
