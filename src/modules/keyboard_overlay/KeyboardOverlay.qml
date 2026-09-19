pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "../common"

Scope {
  id: root
  property bool open: false
  property bool keyHeld: false
  property bool moving: false
  property real positionX: -1
  property real positionY: -1

  function press() {
    if (keyHeld) return;
    keyHeld = true;
    holdTimer.start();
  }
  function release() {
    if (!keyHeld) return;
    holdTimer.stop();
    keyHeld = false;
    if (!moving) toggle();
    moving = false;
  }
  Timer {
    id: holdTimer
    interval: 250
    onTriggered: {
      root.open = true;
      root.moving = true;
    }
  }
  property var snapshot: ({ keys: [], status: "connecting" })
  property string status: "connecting"
  property string message: "Connecting to Glove80…"

  Theme { id: theme }
  ShellConfig { id: shellConfig }

  function toggle() { open = !open; }
  function moveTo(x, y) {
    positionX = Math.max(0, Math.min(x, (panel.screen?.width || 1280) - card.width));
    positionY = Math.max(0, Math.min(y, (panel.screen?.height || 720) - card.height));
  }
  function receive(line) {
    try {
      const state = JSON.parse(line);
      status = state.status;
      if (state.status === "connected") {
        snapshot = state;
        message = "Live · Bluetooth";
      } else {
        message = state.message || (state.status === "sleeping" ? "Keyboard asleep" : "Connecting to Glove80…");
      }
    } catch (error) {
      status = "disconnected";
      message = "Keyboard state unavailable";
    }
  }

  onOpenChanged: {
    if (!open) {
      moving = false;
      keyHeld = false;
      holdTimer.stop();
    }
    if (open) {
      status = "connecting";
      message = "Connecting to Glove80…";
    }
  }

  IpcHandler {
    target: "keyboardOverlay"
    function toggle(): void { root.toggle(); }
    function open(): void { root.open = true; }
    function close(): void { root.open = false; }
    function state(): string { return JSON.stringify({ open: root.open, status: root.status, layer: root.snapshot.layer || "", moving: root.moving, x: card.x, y: card.y }); }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name !== "custom") return;
      switch (String(event.data)) {
      case "desktop-shell:keyboard-overlay:toggle": root.toggle(); break;
      case "desktop-shell:keyboard-overlay:press": root.press(); break;
      case "desktop-shell:keyboard-overlay:release": root.release(); break;
      }
    }
  }

  Process {
    id: reader
    running: root.open
    command: [Quickshell.env("DESKTOP_SHELL_KEYBOARD")]
    stdout: SplitParser { onRead: data => root.receive(data) }
    onExited: {
      if (root.open) {
        root.status = "disconnected";
        root.message = "Keyboard reader stopped · toggle to reconnect";
      }
    }
  }

  PanelWindow {
    id: panel
    visible: root.open
    screen: shellConfig.screen
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    // Only the deliberate F9 hold enables mouse input. Never request keyboard focus.
    WlrLayershell.namespace: "quickshell:keyboardOverlay"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {
      x: card.x
      y: card.y
      width: root.moving ? card.width : 0
      height: root.moving ? card.height : 0
    }

    Rectangle {
      id: card
      width: Math.min(1100, panel.width - 48)
      height: Math.min(440, panel.height * 0.46)
      x: root.positionX < 0 ? (panel.width - width) / 2 : Math.max(0, Math.min(root.positionX, panel.width - width))
      y: root.positionY < 0 ? panel.height - height - 28 : Math.max(0, Math.min(root.positionY, panel.height - height))
      radius: 22
      color: root.moving ? Qt.alpha(theme.bgSolid, 0.14) : "transparent"

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 18
        text: root.status === "connected" ? root.snapshot.layer : ""
        color: Qt.alpha(theme.textPrimary, 0.8)
        style: Text.Outline
        styleColor: Qt.alpha(theme.bgSolid, 0.65)
        font.family: theme.fontFamily
        font.pixelSize: 14
      }

      Item {
        id: board
        x: 22; y: 57
        width: parent.width - 44
        height: parent.height - 80
        opacity: root.status === "connected" ? 1 : 0.32
        readonly property var keys: root.snapshot.keys || []
        readonly property real minX: keys.length ? Math.min(...keys.map(k => k.x - k.w / 2 - 0.25)) : 0
        readonly property real minY: keys.length ? Math.min(...keys.map(k => k.y - k.h / 2 - 0.25)) : 0
        readonly property real spanX: keys.length ? Math.max(...keys.map(k => k.x + k.w / 2 + 0.25)) - minX : 18
        readonly property real spanY: keys.length ? Math.max(...keys.map(k => k.y + k.h / 2 + 0.25)) - minY : 7
        readonly property real unit: Math.min(width / spanX, height / spanY)

        Repeater {
          model: board.keys
          delegate: Rectangle {
            id: key
            required property var modelData
            x: (board.width - board.spanX * board.unit) / 2 + (modelData.x - modelData.w / 2 - board.minX) * board.unit + 2
            y: (board.height - board.spanY * board.unit) / 2 + (modelData.y - modelData.h / 2 - board.minY) * board.unit + 2
            width: modelData.w * board.unit - 4
            height: modelData.h * board.unit - 4
            rotation: modelData.rotation
            radius: 7
            color: Qt.alpha(theme.bgSolid, modelData.disabled ? 0.06 : 0.18)
            border.color: Qt.alpha(modelData.inherited || modelData.disabled ? theme.textMuted : theme.accent, 0.32)
            border.width: 1
            opacity: modelData.disabled ? 0.4 : 1

            Text {
              anchors.centerIn: parent
              anchors.verticalCenterOffset: key.modelData.detail ? -5 : 0
              width: parent.width - 6
              text: key.modelData.label
              color: Qt.alpha(key.modelData.inherited ? theme.textSecondary : theme.textPrimary, 0.9)
              style: Text.Outline
              styleColor: Qt.alpha(theme.bgSolid, 0.75)
              font.family: theme.fontFamily
              font.pixelSize: Math.max(9, Math.min(14, board.unit * 0.27))
              font.weight: Font.Medium
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
              fontSizeMode: Text.Fit
              minimumPixelSize: 8
              maximumLineCount: 2
              elide: Text.ElideRight
            }
            Text {
              anchors.bottom: parent.bottom
              anchors.bottomMargin: 4
              width: parent.width - 4
              x: 2
              text: key.modelData.detail.replace(/^hold /, "↳ ").replace(/Macro /g, "M")
              color: theme.textSecondary
              style: Text.Outline
              styleColor: Qt.alpha(theme.bgSolid, 0.75)
              font.family: theme.fontFamily
              font.pixelSize: Math.max(7, board.unit * 0.15)
              horizontalAlignment: Text.AlignHCenter
              elide: Text.ElideRight
            }
          }
        }
      }

      Text {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 13
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width - 48
        visible: root.status !== "connected"
        text: root.message
        color: theme.warning
        style: Text.Outline
        styleColor: theme.bgSolid
        font.family: theme.fontFamily
        font.pixelSize: 11
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
      }
      MouseArea {
        anchors.fill: parent
        enabled: root.moving
        acceptedButtons: Qt.LeftButton
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        property point startPointer
        property point startPosition
        onPressed: mouse => {
          startPointer = mapToItem(panel.contentItem, mouse.x, mouse.y);
          startPosition = Qt.point(card.x, card.y);
        }
        onPositionChanged: mouse => {
          if (!pressed) return;
          const pointer = mapToItem(panel.contentItem, mouse.x, mouse.y);
          root.moveTo(startPosition.x + pointer.x - startPointer.x,
            startPosition.y + pointer.y - startPointer.y);
        }
      }
    }
  }
}
