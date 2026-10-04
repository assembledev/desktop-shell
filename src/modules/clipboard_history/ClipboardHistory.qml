pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import "../common"

Scope {
  id: root

  Theme {
    id: theme
  }

  ShellConfig { id: shellConfig }
  MotionTransition {
    id: surfaceTransition
    requested: root.open
  }

  property string backend: Quickshell.env("DESKTOP_SHELL_BACKEND")
  property bool open: false
  property bool loading: false
  property bool hydrated: false
  property bool refreshPending: false
  property var entries: []
  property var previewPaths: ({})
  property double ageNow: Date.now() / 1000
  property string message: ""
  property bool wipeArmed: false

  function imageUrl(path) {
    if (!path)
      return "";
    const encoded = encodeURI(path).replace(/#/g, "%23").replace(/\?/g, "%3F");
    return encoded[0] === "/" ? "file://" + encoded : encoded;
  }

  function recordAge(createdAt) {
    if (!(createdAt > 0))
      return "";
    const seconds = Math.max(0, ageNow - createdAt);
    if (seconds < 60)
      return "now";
    if (seconds < 3600)
      return Math.floor(seconds / 60) + "m";
    if (seconds < 86400)
      return Math.floor(seconds / 3600) + "h";
    return Math.floor(seconds / 86400) + "d";
  }

  function displayLabel(item) {
    if (item.image)
      return "Image " + (item.dimensions || "");
    return String(item.label || "").replace(/\s+/g, " ").trim();
  }

  function rememberPreview(entryId, path) {
    if (path.length > 0) {
      const next = Object.assign({}, previewPaths);
      next[entryId] = path;
      previewPaths = next;
    }
  }

  function prunePreviews() {
    const next = ({});
    for (const item of entries) {
      if (previewPaths[item.entryId])
        next[item.entryId] = previewPaths[item.entryId];
    }
    previewPaths = next;
  }

  function applyFilter() {
    if (!open)
      return;
    const query = search.text.toLowerCase().trim();
    filteredModel.clear();

    for (let i = 0; i < entries.length; i++) {
      const item = entries[i];
      const haystack = (displayLabel(item) + " " + (item.kind || "") + " " + (item.dimensions || "")).toLowerCase();
      if (query.length === 0 || haystack.indexOf(query) !== -1)
        filteredModel.append(item);
    }

    if (filteredModel.count > 0 && list.currentIndex < 0)
      list.currentIndex = 0;
    if (filteredModel.count === 0)
      list.currentIndex = -1;
  }

  function refresh(showLoading) {
    if (showLoading && entries.length === 0)
      loading = true;
    if (listProc.running) {
      refreshPending = true;
      return;
    }
    listProc.running = true;
  }

  function openPicker() {
    inputIntent.claimKeyboard();
    ageNow = Date.now() / 1000;
    open = true;
    message = "";
    if (search.text.length > 0)
      search.text = "";
    else
      applyFilter();
    if (!hydrated) {
      loading = true;
      if (!listProc.running)
        refresh(true);
    }
    Qt.callLater(function() { search.forceActiveFocus(); });
  }

  function closePicker() {
    open = false;
  }

  function togglePicker() {
    if (open)
      closePicker();
    else
      openPicker();
  }

  function currentItem() {
    if (list.currentIndex < 0 || list.currentIndex >= filteredModel.count)
      return null;
    return filteredModel.get(list.currentIndex);
  }

  function copyItem(item) {
    if (!item || !item.record || copyProc.running)
      return;
    message = "";
    copyProc.exec([backend, "clipboard", "copy", item.record]);
  }

  function deleteItem(item) {
    if (!item || !item.record)
      return;
    deleteProc.exec([backend, "clipboard", "delete", item.record, item.entryId, item.kind]);
  }

  function wipe() {
    if (!wipeArmed) {
      wipeArmed = true;
      wipeConfirmTimer.restart();
      return;
    }
    wipeArmed = false;
    wipeConfirmTimer.stop();
    wipeProc.running = true;
  }

  Timer {
    interval: 15000
    repeat: true
    running: root.open
    onTriggered: root.ageNow = Date.now() / 1000
  }

  Timer {
    id: wipeConfirmTimer
    interval: 3000
    onTriggered: root.wipeArmed = false
  }

  IpcHandler {
    target: "clipboardHistory"
    function open(): void { root.openPicker(); }
    function close(): void { root.closePicker(); }
    function toggle(): void { root.togglePicker(); }
    function refresh(): void { root.refresh(false); }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "custom" && event.data === "desktop-shell:clipboard-history:open")
        root.openPicker();
    }
  }

  Process {
    id: listProc
    command: [root.backend, "clipboard", "list-json"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          root.entries = JSON.parse(text);
          root.message = "";
          root.hydrated = true;
        } catch (error) {
          root.entries = [];
          root.message = "Failed to read clipboard";
          console.error("clipboard-history: JSON parse failed: " + error);
        }
        root.loading = false;
        root.prunePreviews();
        root.applyFilter();
      }
    }
    onExited: {
      root.loading = false;
      if (root.refreshPending) {
        root.refreshPending = false;
        Qt.callLater(function() { root.refresh(false); });
      }
    }
  }

  Process {
    id: copyProc
    onExited: function(exitCode, exitStatus) {
      if (exitCode === 0 && exitStatus === 0)
        root.closePicker();
      else
        root.message = "Failed to copy clipboard entry";
    }
  }

  Process {
    id: deleteProc
    onExited: root.refresh(false)
  }

  Process {
    id: wipeProc
    command: [root.backend, "clipboard", "wipe"]
    onExited: function(exitCode) {
      if (exitCode === 0)
        root.previewPaths = ({});
      root.refresh(false);
    }
  }

  Component.onCompleted: root.refresh(false)

  ListModel {
    id: filteredModel
  }

  PanelWindow {
    screen: shellConfig.screen
    id: window
    visible: surfaceTransition.presented
    color: "transparent"
    exclusiveZone: 0

    WlrLayershell.namespace: "quickshell:clipboardHistory"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.open
      ? WlrKeyboardFocus.Exclusive
      : WlrKeyboardFocus.None

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    InputIntent {
      id: inputIntent
    }

    Rectangle {
      anchors.fill: parent
      color: theme.surfaceScrim
      opacity: surfaceTransition.progress
    }

    MouseArea {
      anchors.fill: parent
      enabled: root.open
      onClicked: root.closePicker()
    }

    Rectangle {
      id: panel

      width: Math.min(740, window.width - 40)
      height: Math.min(600, window.height - 108)
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.verticalCenter: parent.verticalCenter
      radius: 14
      color: theme.surfaceGlassStrong
      border.color: theme.borderSubtle
      border.width: 1
      clip: true
      opacity: surfaceTransition.progress
      scale: 0.95 + surfaceTransition.progress * 0.05
      transform: Translate {
        y: (1 - surfaceTransition.progress) * 20
      }

      MouseArea {
        anchors.fill: parent
        onClicked: function(mouse) { mouse.accepted = true; }
      }

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12
        opacity: Math.max(0, Math.min(1, (surfaceTransition.progress - 0.14) / 0.86))

        RowLayout {
          Layout.fillWidth: true
          spacing: 12

          Text {
            Layout.fillWidth: true
            text: "Clipboard"
            color: theme.textPrimary
            font.family: theme.uiFontFamily
            font.pixelSize: 20
            font.bold: true
            elide: Text.ElideRight
          }

          Text {
            text: String(filteredModel.count)
            color: theme.textMuted
            font.family: theme.uiFontFamily
            font.pixelSize: 12
            font.bold: true
          }

          IconButton {
            glyph: "refresh"
            tooltip: "Refresh clipboard history"
            onClicked: root.refresh(true)
          }

          IconButton {
            glyph: root.wipeArmed ? "warning" : "trash"
            tooltip: root.wipeArmed ? "Click again to wipe" : "Wipe clipboard history"
            danger: true
            onClicked: root.wipe()
          }
        }

        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 44
          radius: 10
          color: theme.surfaceMuted
          border.color: search.activeFocus ? theme.accent : theme.borderMuted
          border.width: 1

          ShellSymbol {
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            symbol: "search"
            tint: search.activeFocus ? theme.accent : theme.textMuted
            size: 18
          }

          TextInput {
            id: search
            anchors.left: parent.left
            anchors.leftMargin: 42
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            color: theme.textPrimary
            selectionColor: theme.selectedBg
            selectedTextColor: theme.textPrimary
            font.family: theme.uiFontFamily
            font.pixelSize: 13
            clip: true
            focus: true
            onTextChanged: root.applyFilter()

            Keys.onDownPressed: {
              inputIntent.claimKeyboard();
              list.forceActiveFocus();
              list.incrementCurrentIndex();
            }
            Keys.onReturnPressed: root.copyItem(root.currentItem())
            Keys.onEnterPressed: root.copyItem(root.currentItem())
            Keys.onEscapePressed: root.closePicker()
          }
        }

        ListView {
          id: list
          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true
          spacing: 4
          model: filteredModel
          highlightFollowsCurrentItem: false

          onCurrentIndexChanged: {
            if (currentIndex >= 0)
              Qt.callLater(function() { list.positionViewAtIndex(list.currentIndex, ListView.Contain); });
          }

          highlight: Rectangle {
            width: list.width
            height: list.currentItem?.height || 0
            y: list.currentItem?.y || 0
            radius: 10
            color: theme.surfaceRaised
            border.width: 1
            border.color: theme.accent
            z: 1

            Behavior on y {
              MotionNumberAnimation { role: MotionNumberAnimation.FocusTravel }
            }
            Behavior on height {
              MotionNumberAnimation { role: MotionNumberAnimation.FocusTravel }
            }


          }

          add: Transition {
            ParallelAnimation {
              MotionNumberAnimation {
                property: "opacity"
                from: 0
                to: 1
                role: MotionNumberAnimation.Content
              }
              MotionNumberAnimation {
                property: "x"
                from: 12
                to: 0
                role: MotionNumberAnimation.Content
              }
            }
          }
          remove: Transition {
            ParallelAnimation {
              MotionNumberAnimation {
                property: "opacity"
                to: 0
                role: MotionNumberAnimation.SurfaceExit
              }
              MotionNumberAnimation {
                property: "x"
                to: -8
                role: MotionNumberAnimation.SurfaceExit
              }
            }
          }
          displaced: Transition {
            MotionNumberAnimation {
              properties: "x,y"
              role: MotionNumberAnimation.FocusTravel
            }
          }

          Keys.onEscapePressed: root.closePicker()
          Keys.onReturnPressed: root.copyItem(root.currentItem())
          Keys.onEnterPressed: root.copyItem(root.currentItem())
          Keys.onPressed: event => {
            if (event.key === Qt.Key_Up || event.key === Qt.Key_Down
                || event.key === Qt.Key_PageUp || event.key === Qt.Key_PageDown
                || event.key === Qt.Key_Home || event.key === Qt.Key_End)
              inputIntent.claimKeyboard();
            if (event.key === Qt.Key_Backspace) {
              search.forceActiveFocus();
              if (search.text.length > 0)
                search.text = search.text.slice(0, -1);
              event.accepted = true;
            }
          }

          ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
            width: 4
          }

          delegate: Rectangle {
            id: item

            required property int index
            required property string entryId
            required property string label
            required property string record
            required property string preview
            required property string kind
            required property string dimensions
            required property bool image
            required property string size
            required property double createdAt

            readonly property bool selected: ListView.isCurrentItem
            readonly property bool link: !image && /^https?:\/\/[^\s]+$/i.test(label.trim())
            readonly property string cleanLabel: root.displayLabel(item)
            readonly property string previewPath: root.previewPaths[entryId] || preview

            width: ListView.view.width
            height: image ? 112 : 64
            radius: 10
            color: !selected && inputIntent.pointerActive && rowMouse.containsMouse
              ? theme.surfaceHover
              : "transparent"
            border.width: 1
            border.color: "transparent"
            clip: true
            scale: rowMouse.pressed ? 0.99 : 1
            z: 2

            Behavior on color {
              MotionColorAnimation { role: MotionNumberAnimation.Feedback }
            }
            Behavior on scale {
              MotionNumberAnimation { role: MotionNumberAnimation.Feedback }
            }

            MouseArea {
              id: rowMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.copyItem(item)
            }

            Component.onCompleted: {
              if (item.image && item.previewPath.length === 0)
                previewProc.running = true;
            }

            Process {
              id: previewProc
              command: [root.backend, "clipboard", "preview", item.record, item.entryId, item.kind]
              stdout: StdioCollector {
                onStreamFinished: root.rememberPreview(item.entryId, text.trim())
              }
            }

            RowLayout {
              anchors.fill: parent
              anchors.margins: 10
              spacing: 12

              Rectangle {
                Layout.preferredWidth: item.image ? 168 : 28
                Layout.preferredHeight: item.image ? 92 : 28
                radius: 7
                color: item.image ? theme.surfaceMuted : "transparent"
                border.width: item.image ? 1 : 0
                border.color: theme.border
                clip: true

                Image {
                  visible: item.image && item.previewPath.length > 0
                  anchors.fill: parent
                  anchors.margins: 1
                  source: root.imageUrl(item.previewPath)
                  sourceSize.width: Math.max(1, Math.ceil(width * Screen.devicePixelRatio))
                  sourceSize.height: Math.max(1, Math.ceil(height * Screen.devicePixelRatio))
                  asynchronous: true
                  fillMode: Image.PreserveAspectFit
                  smooth: true
                }

                ShellSymbol {
                  visible: !item.image || item.previewPath.length === 0
                  anchors.centerIn: parent
                  symbol: item.image ? "image" : item.link ? "link" : "document"
                  tint: item.image ? theme.info : theme.textSecondary
                  size: item.image ? 28 : 20
                }

              }

              ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 5

                Text {
                  Layout.fillWidth: true
                  text: item.image ? "Image" : item.cleanLabel
                  textFormat: Text.PlainText
                  color: theme.textPrimary
                  font.family: theme.uiFontFamily
                  font.pixelSize: item.image ? 15 : 13
                  wrapMode: Text.Wrap
                  elide: Text.ElideRight
                  maximumLineCount: item.image ? 1 : 2
                }

                Text {
                  visible: item.image
                  Layout.fillWidth: true
                  text: [item.kind.toUpperCase(), item.dimensions.replace("x", " × "), item.size].filter(Boolean).join(" · ")
                  color: theme.textMuted
                  font.family: theme.uiFontFamily
                  font.pixelSize: 11
                  elide: Text.ElideRight
                }
              }

              Item {
                Layout.preferredWidth: 40
                Layout.fillHeight: true

                Text {
                  anchors.top: parent.top
                  anchors.right: parent.right
                  text: root.recordAge(item.createdAt)
                  color: theme.textMuted
                  font.family: theme.uiFontFamily
                  font.pixelSize: 11
                }

                IconButton {
                  anchors.right: parent.right
                  anchors.bottom: parent.bottom
                  width: 28
                  height: 28
                  glyph: "trash"
                  visible: item.selected || activeFocus || hovered || (inputIntent.pointerActive && rowMouse.containsMouse)
                  tooltip: "Delete entry"
                  onClicked: root.deleteItem(item)
                }
              }
            }

          }
        }

        Text {
          Layout.fillWidth: true
          visible: root.loading || filteredModel.count === 0 || root.message.length > 0
          text: root.message.length > 0 ? root.message : root.loading ? "Loading..." : "Clipboard is empty"
          color: theme.textSecondary
          font.family: theme.uiFontFamily
          font.pixelSize: 13
          horizontalAlignment: Text.AlignHCenter
        }
      }
    }

    Shortcut {
      sequence: "Esc"
      onActivated: root.closePicker()
    }
  }

  component IconButton: ShellButton {
    colors: theme
    property bool danger: false
    accent: danger ? theme.danger : theme.accent
    flatAction: true
  }
}
