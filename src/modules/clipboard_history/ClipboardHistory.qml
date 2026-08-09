pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
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
  property var entries: []
  property string message: ""
  property bool wipeArmed: false

  function imageUrl(path) {
    if (!path)
      return "";
    const encoded = encodeURI(path).replace(/#/g, "%23").replace(/\?/g, "%3F");
    return encoded[0] === "/" ? "file://" + encoded : encoded;
  }

  function displayLabel(item) {
    if (item.image)
      return "Image " + (item.dimensions || "");
    return String(item.label || "").replace(/\s+/g, " ").trim();
  }

  function applyFilter() {
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

  function refresh() {
    loading = true;
    listProc.running = false;
    listProc.running = true;
  }

  function openPicker() {
    open = true;
    message = "";
    search.text = "";
    refresh();
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
    if (!item || !item.record)
      return;
    copyProc.exec([backend, "clipboard", "copy", item.record]);
    closePicker();
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
    id: wipeConfirmTimer
    interval: 3000
    onTriggered: root.wipeArmed = false
  }

  IpcHandler {
    target: "clipboardHistory"
    function open(): void { root.openPicker(); }
    function close(): void { root.closePicker(); }
    function toggle(): void { root.togglePicker(); }
    function refresh(): void {
      if (root.open)
        root.refresh();
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
        } catch (error) {
          root.entries = [];
          root.message = "Failed to read clipboard";
          console.error("clipboard-history: JSON parse failed: " + error);
        }
        root.loading = false;
        root.applyFilter();
      }
    }
    onExited: root.loading = false
  }

  Process {
    id: copyProc
  }

  Process {
    id: deleteProc
    onExited: root.refresh()
  }

  Process {
    id: wipeProc
    command: [root.backend, "clipboard", "wipe"]
    onExited: root.refresh()
  }

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
            color: theme.foreground
            font.family: theme.fontFamily
            font.pixelSize: 22
            font.bold: true
            elide: Text.ElideRight
          }

          Text {
            text: String(filteredModel.count)
            color: theme.terminalBlue
            font.family: theme.fontFamily
            font.pixelSize: 13
            font.bold: true
          }

          IconButton {
            icon: ""
            tooltip: "Refresh"
            onClicked: root.refresh()
          }

          IconButton {
            icon: root.wipeArmed ? "󰗠" : "󰆴"
            tooltip: root.wipeArmed ? "Click again to wipe" : "Wipe clipboard history"
            danger: true
            onClicked: root.wipe()
          }
        }

        Rectangle {
          Layout.fillWidth: true
          height: 44
          radius: 10
          color: theme.surfaceMuted
          border.color: search.activeFocus ? theme.blue : theme.borderMuted
          border.width: 1

          Text {
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            text: ""
            color: theme.blue
            font.family: theme.fontFamily
            font.pixelSize: 14
          }

          TextInput {
            id: search
            anchors.left: parent.left
            anchors.leftMargin: 42
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            color: theme.foreground
            selectionColor: theme.selectedBg
            selectedTextColor: theme.foreground
            font.family: theme.fontFamily
            font.pixelSize: 13
            clip: true
            focus: true
            onTextChanged: root.applyFilter()

            Keys.onDownPressed: {
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
            color: theme.surfaceMuted
            border.width: 1
            border.color: Qt.alpha(theme.blue, 0.46)
            z: 1

            Behavior on y {
              MotionNumberAnimation { role: MotionNumberAnimation.FocusTravel }
            }
            Behavior on height {
              MotionNumberAnimation { role: MotionNumberAnimation.FocusTravel }
            }

            Rectangle {
              anchors.left: parent.left
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              width: 3
              radius: 2
              color: theme.blue
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

            readonly property bool selected: ListView.isCurrentItem
            readonly property string cleanLabel: root.displayLabel(item)
            property string previewPath: preview

            width: ListView.view.width
            height: image ? 172 : 78
            radius: 10
            color: !selected && rowMouse.containsMouse ? theme.surfaceAccent : "transparent"
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
              onEntered: list.currentIndex = item.index
              onClicked: root.copyItem(item)
            }

            Component.onCompleted: {
              if (item.image)
                previewProc.running = true;
            }

            Process {
              id: previewProc
              command: [root.backend, "clipboard", "preview", item.record, item.entryId, item.kind]
              stdout: StdioCollector {
                onStreamFinished: item.previewPath = text.trim()
              }
            }

            RowLayout {
              anchors.fill: parent
              anchors.margins: 10
              spacing: 12

              Rectangle {
                Layout.preferredWidth: item.image ? 210 : 46
                Layout.preferredHeight: item.image ? 132 : 46
                radius: 7
                color: item.image ? theme.surfaceMuted : Qt.alpha(theme.blue, 0.14)
                border.width: item.image ? 1 : 0
                border.color: theme.border
                clip: true

                Image {
                  visible: item.image && item.previewPath.length > 0
                  anchors.fill: parent
                  anchors.margins: 1
                  source: root.imageUrl(item.previewPath)
                  asynchronous: true
                  fillMode: Image.PreserveAspectFit
                  smooth: true
                }

                Text {
                  visible: !item.image || item.previewPath.length === 0
                  anchors.centerIn: parent
                  text: item.image ? "󰋩" : "󰅍"
                  color: item.image ? theme.blue : theme.foreground
                  font.family: theme.fontFamily
                  font.pixelSize: item.image ? 28 : 20
                }
              }

              ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 5

                RowLayout {
                  visible: item.image
                  Layout.fillWidth: true
                  spacing: 8

                  Text {
                    Layout.fillWidth: true
                    text: "Image"
                    color: theme.foreground
                    font.family: theme.fontFamily
                    font.pixelSize: 15
                    font.bold: item.selected
                    elide: Text.ElideRight
                    maximumLineCount: 1
                  }

                  Text {
                    text: item.dimensions
                    color: theme.blue
                    font.family: theme.fontFamily
                    font.pixelSize: 11
                  }
                }

                Text {
                  Layout.fillWidth: true
                  Layout.fillHeight: true
                  text: item.image ? item.label : item.cleanLabel
                  textFormat: Text.PlainText
                  color: item.image ? theme.mutedAlt : theme.foreground
                  font.family: theme.fontFamily
                  font.pixelSize: item.image ? 11 : 13
                  wrapMode: item.image ? Text.NoWrap : Text.Wrap
                  elide: item.image ? Text.ElideRight : Text.ElideNone
                  maximumLineCount: item.image ? 1 : 3
                  verticalAlignment: Text.AlignVCenter
                }
              }

              IconButton {
                icon: "󰆴"
                tooltip: "Delete"
                danger: true
                visible: item.selected || rowMouse.containsMouse
                onClicked: root.deleteItem(item)
              }
            }

          }
        }

        Text {
          Layout.fillWidth: true
          visible: root.loading || filteredModel.count === 0 || root.message.length > 0
          text: root.message.length > 0 ? root.message : root.loading ? "Loading..." : "Clipboard is empty"
          color: theme.muted
          font.family: theme.fontFamily
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

  component IconButton: Rectangle {
    id: button

    property string icon: ""
    property string tooltip: ""
    property bool danger: false
    signal clicked()

    Layout.preferredWidth: 38
    Layout.preferredHeight: 38
    radius: 8
    color: mouse.pressed ? theme.selectedBg : mouse.containsMouse ? theme.surfaceAccent : "transparent"
    border.width: 1
    border.color: mouse.containsMouse ? (danger ? Qt.alpha(theme.red, 0.45) : theme.borderSubtle) : "transparent"
    scale: mouse.pressed ? 0.9 : 1

    Behavior on color {
      MotionColorAnimation { role: MotionNumberAnimation.Feedback }
    }
    Behavior on border.color {
      MotionColorAnimation { role: MotionNumberAnimation.Feedback }
    }
    Behavior on scale {
      MotionNumberAnimation { role: MotionNumberAnimation.Feedback }
    }

    Text {
      anchors.centerIn: parent
      text: button.icon
      color: button.danger ? theme.red : theme.foreground
      font.family: theme.fontFamily
      font.pixelSize: 14
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: button.clicked()
    }

    ToolTip.visible: mouse.containsMouse && button.tooltip.length > 0
    ToolTip.text: button.tooltip
    ToolTip.delay: 400
  }
}
