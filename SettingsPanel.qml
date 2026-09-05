import QtQuick
import QtQuick.Controls as Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui as Ui

Item {
  id: root
  required property var taskbar
  property bool opened: false
  property var savedConfig: ({})
  property var draft: ({})
  property var schema: ({})
  property var meta: ({groups:[],fields:{},choices:{}})
  property var fields: []
  property int category: 0
  property string query: ""
  property string error: ""
  property string status: ""
  property var editing: null
  property bool discardPrompt: false
  readonly property var changes: changesForDraft()
  readonly property bool dirty: Object.keys(changes).length > 0
  readonly property var visibleFields: fields.filter(f => query.trim()
    ? (f.label+" "+f.description+" "+f.path).toLowerCase().includes(query.trim().toLowerCase())
    : meta.groups[category]?.sections.includes(f.section))
  function clone(value) { return JSON.parse(JSON.stringify(value)) }
  function changesForDraft() {
    var result = {}
    for (var section in savedConfig) {
      if (typeof savedConfig[section] !== "object" || !draft[section]) continue
      for (var key in savedConfig[section]) {
        if (JSON.stringify(savedConfig[section][key]) !== JSON.stringify(draft[section]?.[key]))
          result[section+"."+key] = {before:savedConfig[section][key],after:draft[section][key]}
      }
    }
    return result
  }
  function open() {
    taskbar.close(); taskbar.switcherView.close(); opened = true; discardPrompt = false
    if (!dirty) request("read")
    Qt.callLater(() => search.forceActiveFocus())
  }
  function dismiss() {
    if (discardPrompt) { discardPrompt=false; return }
    if (editing) { editing = null; error = ""; rows.forceActiveFocus(); return }
    if (dirty) discardPrompt = true
    else opened = false
  }
  function request(operation) {
    if (bridge.running) return
    error = ""; status = ""
    bridge.operation = operation
    bridge.command = ["python3", Qt.resolvedUrl("settings-ui.py").toString().replace(/^file:\/\//,""), operation]
    if (operation === "apply") bridge.command = bridge.command.concat([JSON.stringify(changes)])
    bridge.running = true
  }
  function finish(result) {
    if (result.config) {
      savedConfig = clone(result.config); draft = clone(result.config)
      if (result.schema) { schema = result.schema; meta = result.meta; buildFields() }
      status = bridge.operation === "apply" ? "Changes applied" : ""
    }
    error = result.error || ""
  }
  function buildFields() {
    var result = []
    for (var section in schema.properties) {
      if (section === "schemaVersion") continue
      for (var key in schema.properties[section].properties) {
        var path = section+"."+key, spec = schema.properties[section].properties[key]
        var info = meta.fields[path] || {label:key,description:""}
        if (path === "keyboard.slots") {
          for(var i=0;i<10;i++) result.push({path:path,section:section,key:key,slot:i,label:"Activate slot "+((i+1)%10),description:"Press this shortcut to act on icon "+(i+1)+" in the taskbar, counting from the left. It has the same effect as clicking that icon. Dragging icons changes which window this shortcut controls. Leave empty to disable it.",spec:{type:"string",default:spec.default[i]}})
        } else result.push({path:path,section:section,key:key,slot:-1,label:info.label,description:info.description,spec:spec})
      }
    }
    fields = result
  }
  function value(field) {
    var current = draft[field.section]?.[field.key]
    return field.slot >= 0 ? current?.[field.slot] : current
  }
  function put(field, next) {
    var updated = clone(draft)
    if (field.slot >= 0) updated[field.section][field.key][field.slot] = next
    else updated[field.section][field.key] = next
    draft = updated; status = ""; error = ""
  }
  function display(field) {
    var v = value(field)
    if (field.spec.type === "boolean") return v ? "On" : "Off"
    if (field.spec.enum) return meta.choices[v] || v
    if (field.path === "workspace.modes") return Object.keys(v || {}).length+" workspaces"
    if (Array.isArray(v)) return v.length ? v.length+" applications" : "None"
    return String(v ?? "") || "Disabled"
  }
  function activate(field) {
    if (!field || bridge.running) return
    if (field.spec.type === "boolean") { put(field,!value(field)); return }
    editing = field; error = ""
    var v = value(field)
    editor.text = field.path === "workspace.modes" ? Object.keys(v).map(k => k+" = "+(v[k]?"floating":"tiled")).join("\n") : Array.isArray(v) ? v.join("\n") : String(v)
    choiceList.currentIndex = field.spec.enum ? Math.max(0,field.spec.enum.indexOf(v)) : 0
    Qt.callLater(() => { if (field.spec.enum) choiceList.forceActiveFocus(); else { editor.forceActiveFocus(); editor.selectAll() } })
  }
  function acceptEditor() {
    if (!editing) return
    try {
      var text = editor.text, spec = editing.spec, next
      if (spec.enum) next = spec.enum[choiceList.currentIndex]
      else if (spec.type === "integer" || spec.type === "number") {
        if (!text.trim()) throw "Enter a number."
        next = Number(text)
        if (!isFinite(next) || (spec.type === "integer" && !Number.isInteger(next))) throw "Enter a valid "+(spec.type === "integer" ? "whole number." : "number.")
        if (next < spec.minimum || next > spec.maximum) throw "Use a value from "+spec.minimum+" to "+spec.maximum+"."
      } else if (editing.path === "workspace.modes") {
        next = {}
        for (var line of text.split("\n").filter(l => l.trim())) {
          var match = line.match(/^\s*(.+?)\s*=\s*(floating|tiled)\s*$/i)
          if (!match) throw "Use one workspace per line, such as 1 = floating or 3 = tiled."
          next[match[1]] = match[2].toLowerCase() === "floating"
        }
      } else if (spec.type === "array") next = text.split("\n").map(l => l.trim()).filter(l => l)
      else next = text.trim()
      put(editing,next); editing = null; rows.forceActiveFocus()
    } catch (message) { error = String(message) }
  }
  function resetField() { if (editing) { put(editing,clone(editing.spec.default)); editing=null; rows.forceActiveFocus() } }
  onVisibleFieldsChanged: { rows.currentIndex = 0; rows.contentY = 0 }
  Process {
    id: bridge
    property string operation: ""
    stdout: StdioCollector { onStreamFinished: { try { root.finish(JSON.parse(text)) } catch(e) { root.error = "Could not read settings: "+e } } }
    stderr: StdioCollector { onStreamFinished: if (text.trim()) root.error = text.trim() }
  }
  PanelWindow {
    id: panel
    screen: root.taskbar.surface?.screen || null
    visible: root.opened
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-taskbar-settings"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    Rectangle { anchors.fill: parent; color: Color.menu.scrim }
    MouseArea { anchors.fill: parent; onClicked: root.dismiss() }
    Rectangle {
      id: frame
      anchors.centerIn: parent
      width: Math.min(920,parent.width-60)
      height: Math.min(680,parent.height-60)
      color: Color.menu.background
      radius: 0
      border.color: Color.menu.border
      border.width: 2
      MouseArea { anchors.fill: parent; onClicked: {} }
      Shortcut { sequence: "Escape"; enabled: root.opened; onActivated: root.dismiss() }
      Shortcut { sequence: "Ctrl+S"; enabled: root.opened && !root.editing && !root.discardPrompt && root.dirty && !bridge.running; onActivated: root.request("apply") }
      Shortcut { sequence: "Ctrl+F"; enabled: root.opened && !root.editing; onActivated: search.forceActiveFocus() }
      Text {
        x: 24; y: 22; text: "Taskbar settings"; color: Color.menu.text
        font.family: Style.font.menuFamily; font.pixelSize: Style.font.display
      }
      Ui.Button { anchors.right: parent.right; anchors.rightMargin: 20; y: 18; text: "Close"; radius: 0; focusable: true; foreground: Color.menu.text; onClicked: root.dismiss() }
      Ui.TextField {
        id: search
        x: 24; y: 66; width: parent.width-48; height: 38
        placeholderText: "Search settings…"; foreground: Color.menu.text; font.family: Style.font.menuFamily
        onTextChanged: root.query = text
        background: Rectangle { color: "transparent"; radius: 0; border.width: search.activeFocus ? 2 : 1; border.color: search.activeFocus ? Color.lock.borderActive : Util.alpha(Color.menu.text,.25) }
        Keys.onDownPressed: rows.forceActiveFocus()
        Keys.onReturnPressed: { rows.forceActiveFocus(); root.activate(root.visibleFields[rows.currentIndex]) }
      }
      Column {
        x: 24; y: 122; width: 152; spacing: 3
        Repeater {
          model: root.meta.groups
          Ui.Button {
            required property var modelData
            required property int index
            width: parent.width; height: 38; text: modelData.label
            radius: 0; focusable: true; leftAlign: true; selected: root.category === index && !root.query
            foreground: Color.menu.text
            onClicked: { root.category=index; search.text=""; rows.forceActiveFocus() }
          }
        }
      }
      Rectangle { x: 193; y: 122; width: 1; height: parent.height-220; color: Util.alpha(Color.menu.text,.18) }
      ListView {
        id: rows
        x: 211; y: 122; width: parent.width-x-24; height: parent.height-y-191
        model: root.visibleFields
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        activeFocusOnTab: true
        keyNavigationEnabled: true
        highlightMoveDuration: 0
        spacing: 2
        Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded; contentItem: Rectangle { implicitWidth: 4; implicitHeight: 80; radius: 0; color: Util.alpha(Color.menu.text,.4) } }
        Keys.onReturnPressed: root.activate(root.visibleFields[currentIndex])
        Keys.onEnterPressed: root.activate(root.visibleFields[currentIndex])
        Keys.onSpacePressed: root.activate(root.visibleFields[currentIndex])
        Keys.onLeftPressed: {
          var f=root.visibleFields[currentIndex]; if (!f) return
          if (f.spec.type === "boolean") root.put(f,false)
          else if (f.spec.enum) root.put(f,f.spec.enum[(f.spec.enum.indexOf(root.value(f))+f.spec.enum.length-1)%f.spec.enum.length])
        }
        Keys.onRightPressed: {
          var f=root.visibleFields[currentIndex]; if (!f) return
          if (f.spec.type === "boolean") root.put(f,true)
          else if (f.spec.enum) root.put(f,f.spec.enum[(f.spec.enum.indexOf(root.value(f))+1)%f.spec.enum.length])
          else root.activate(f)
        }
        delegate: Rectangle {
          required property var modelData
          required property int index
          readonly property bool highlighted: rows.currentIndex===index
          width: rows.width-10; height: 48; radius: 0
          color: highlighted ? Color.menu.selectedBackground : "transparent"
          border.width: highlighted && rows.activeFocus ? 1 : 0
          border.color: Color.lock.borderActive
          Text {
            x: 12; anchors.verticalCenter: parent.verticalCenter; width: parent.width*.57-18
            text: modelData.label; elide: Text.ElideRight; textFormat: Text.PlainText
            color: highlighted ? Color.menu.selectedText : Color.menu.text
            font.family: Style.font.menuFamily; font.pixelSize: Style.font.heading
          }
          Text {
            anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; width: parent.width*.43-12
            text: root.display(modelData)+(modelData.spec.type === "boolean" ? "" : "  ›")
            horizontalAlignment: Text.AlignRight; elide: Text.ElideRight; textFormat: Text.PlainText
            color: highlighted ? Color.menu.selectedText : Color.menu.text
            opacity: highlighted ? 1 : .72
            font.family: Style.font.menuFamily; font.pixelSize: Style.font.body
          }
          MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onEntered: rows.currentIndex=index; onClicked: { rows.currentIndex=index; rows.forceActiveFocus(); root.activate(modelData) } }
        }
      }
      Text {
        visible: !root.visibleFields.length && !bridge.running
        anchors.centerIn: rows; text: "No matching settings"; color: Color.menu.text
        font.family: Style.font.menuFamily; font.pixelSize: Style.font.heading
      }
      Controls.ScrollView {
        id: helpScroll
        x: rows.x+12; y: rows.y+rows.height+10; width: rows.width-22; height: 100
        clip: true
        contentWidth: availableWidth
        Text {
          width: helpScroll.availableWidth
          text: root.visibleFields[rows.currentIndex]?.description || "Choose a setting to see what it changes."
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          color: Util.alpha(Color.menu.text,.85)
          font.family: Style.font.menuFamily; font.pixelSize: Style.font.heading
        }
      }
      Rectangle { x: 24; y: parent.height-70; width: parent.width-48; height: 1; color: Util.alpha(Color.menu.text,.18) }
      Text {
        x: 24; y: parent.height-53; width: parent.width-350; height: 40
        text: root.error || (bridge.running ? "Saving…" : root.dirty ? "Changes not yet applied" : root.status || "Enter to edit · Ctrl+S to apply")
        wrapMode: Text.WordWrap; maximumLineCount: 2; textFormat: Text.PlainText
        color: root.error ? Color.lock.textError : Color.menu.text
        font.family: Style.font.menuFamily; font.pixelSize: Style.font.bodySmall
      }
      Row {
        anchors.right: parent.right; anchors.rightMargin: 24; y: parent.height-54; spacing: 12
        Ui.Button { text: "Discard"; radius: 0; focusable: true; enabled: root.dirty && !bridge.running; opacity: enabled?1:.4; foreground: Color.menu.text; onClicked: { root.draft=root.clone(root.savedConfig); root.error=""; root.status="Changes discarded" } }
        Ui.Button { text: "Apply changes"; radius: 0; focusable: true; bordered: true; enabled: root.dirty && !bridge.running; opacity: enabled?1:.4; foreground: Color.menu.text; onClicked: root.request("apply") }
      }
      Rectangle {
        anchors.fill: parent; visible: root.editing !== null || root.discardPrompt
        color: Color.menu.scrim
        MouseArea { anchors.fill: parent; onClicked: {} }
        Rectangle {
          anchors.centerIn: parent; width: Math.min(620,parent.width-64)
          height: root.discardPrompt ? 190 : Math.min(470,frame.height-80)
          color: Color.menu.background; border.color: Color.lock.borderActive; border.width: 2; radius: 0
          Text { x: 24; y: 22; width: parent.width-48; text: root.discardPrompt ? "Discard unapplied changes?" : root.editing?.label || ""; color: Color.menu.text; font.family: Style.font.menuFamily; font.pixelSize: Style.font.heading; textFormat: Text.PlainText }
          Text { x: 24; y: 58; width: parent.width-48; height: 92; visible: !root.discardPrompt; text: root.editing?.description || ""; wrapMode: Text.WordWrap; maximumLineCount: 6; elide: Text.ElideRight; color: Util.alpha(Color.menu.text,.85); font.family: Style.font.menuFamily; font.pixelSize: Style.font.body; textFormat: Text.PlainText }
          ListView {
            id: choiceList
            x: 24; y: 160; width: parent.width-48; height: parent.height-y-96
            visible: !!root.editing?.spec.enum; model: root.editing?.spec.enum || []; clip: true
            keyNavigationEnabled: true; highlightMoveDuration: 0
            Keys.onReturnPressed: root.acceptEditor()
            Keys.onEnterPressed: root.acceptEditor()
            delegate: Rectangle {
              required property string modelData
              required property int index
              width: choiceList.width; height: 36; color: choiceList.currentIndex===index ? Color.menu.selectedBackground : "transparent"
              Text { x: 10; anchors.verticalCenter: parent.verticalCenter; text: root.meta.choices[modelData] || modelData; color: choiceList.currentIndex===index ? Color.menu.selectedText : Color.menu.text; font.family: Style.font.menuFamily; font.pixelSize: Style.font.body }
              MouseArea { anchors.fill: parent; onClicked: { choiceList.currentIndex=index; root.acceptEditor() } }
            }
          }
          Controls.ScrollView {
            x: 24; y: 160; width: parent.width-48; height: parent.height-y-96
            visible: !!root.editing && !root.editing.spec.enum; clip: true
            Controls.TextArea {
              id: editor
              color: Color.menu.text; selectionColor: Color.lock.selection; selectedTextColor: Color.menu.text
              font.family: Style.font.menuFamily; font.pixelSize: Style.font.body
              wrapMode: TextEdit.Wrap; padding: 12; selectByMouse: true
              background: Rectangle { color: "transparent"; border.width: 1; border.color: Color.lock.borderActive; radius: 0 }
              Keys.onPressed: event => {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  if (event.modifiers & Qt.ControlModifier || (root.editing?.spec.type !== "array" && root.editing?.path !== "workspace.modes")) { root.acceptEditor(); event.accepted=true }
                }
              }
            }
          }
          Text { x: 24; y: parent.height-89; width: parent.width-48; height: 35; text: root.discardPrompt ? "Your saved settings will stay as they are." : root.error; color: root.error && !root.discardPrompt ? Color.lock.textError : Color.menu.text; font.family: Style.font.menuFamily; font.pixelSize: Style.font.bodySmall; wrapMode: Text.WordWrap; textFormat: Text.PlainText }
          Row {
            anchors.right: parent.right; anchors.rightMargin: 24; y: parent.height-48; spacing: 12
            Ui.Button { text: "Default"; visible: !root.discardPrompt; radius: 0; focusable: true; foreground: Color.menu.text; onClicked: root.resetField() }
            Ui.Button { text: root.discardPrompt ? "Keep editing" : "Cancel"; radius: 0; focusable: true; foreground: Color.menu.text; onClicked: { root.discardPrompt=false; root.editing=null; root.error=""; rows.forceActiveFocus() } }
            Ui.Button { text: root.discardPrompt ? "Discard" : "Done"; radius: 0; focusable: true; bordered: true; foreground: Color.menu.text; onClicked: { if (root.discardPrompt) { root.draft=root.clone(root.savedConfig); root.discardPrompt=false; root.opened=false } else root.acceptEditor() } }
          }
        }
      }
    }
  }
}
