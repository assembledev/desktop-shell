import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../common"

Scope {
  id: root

  ShellConfig { id: shellConfig }

  property string backend: Quickshell.env("DESKTOP_SHELL_BACKEND")
  property string defaultWallpaper: Quickshell.env("DESKTOP_SHELL_DEFAULT_WALLPAPER")
  property string wallpaperStateDir: Quickshell.env("WALLPAPER_PICKER_STATE_DIR")
  property string wallpaperPath: defaultWallpaper
  property bool open: false
  property string clockText: ""
  property string dateText: ""

  function updateClock() {
    const now = new Date();
    clockText = Qt.formatDateTime(now, "HH:mm");
    dateText = Qt.formatDateTime(now, "dddd, MMMM dd");
  }

  Component.onCompleted: updateClock()

  Timer {
    interval: 1000
    running: root.open
    repeat: true
    onTriggered: root.updateClock()
  }

  IpcHandler {
    target: "lockPreview"
    function open(): void {
      root.updateClock();
      root.open = true;
    }
    function close(): void { root.open = false; }
    function toggle(): void {
      root.updateClock();
      root.open = !root.open;
    }
  }

  FileView {
    path: root.wallpaperStateDir + "/current"
    preload: true
    watchChanges: true
    onLoaded: {
      const next = text().trim();
      root.wallpaperPath = next.length > 0 ? next : root.defaultWallpaper;
    }
    onTextChanged: {
      const next = text().trim();
      root.wallpaperPath = next.length > 0 ? next : root.defaultWallpaper;
    }
    onLoadFailed: function() {
      root.wallpaperPath = root.defaultWallpaper;
    }
  }

  PanelWindow {
    screen: shellConfig.screen
    id: previewWindow
    visible: root.open
    color: "transparent"
    WlrLayershell.namespace: "quickshell:lockPreview"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    LockView {
      anchors.fill: parent
      wallpaperPath: root.wallpaperPath
      clockText: root.clockText
      dateText: root.dateText
      userText: Quickshell.env("USER") || Quickshell.env("LOGNAME")
      keyboardText: shellConfig.keyboardLayoutLabel(0)
      batteryVisible: true
      batteryText: "󰂄 44%"
      passwordLength: 0
      message: ""
      failed: false
      authRunning: false

      onClear: root.open = false
    }
  }
}
