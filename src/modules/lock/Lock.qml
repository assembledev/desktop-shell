import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Wayland
import "../common"

Scope {
  id: root

  Theme {
    id: theme
  }

  ShellConfig {
    id: shellConfig
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
  }

  property string backend: Quickshell.env("DESKTOP_SHELL_BACKEND")
  property string wallpaperStateDir: Quickshell.env("WALLPAPER_PICKER_STATE_DIR")
  property string defaultWallpaper: Quickshell.env("DESKTOP_SHELL_DEFAULT_WALLPAPER")
  property string wallpaperPath: defaultWallpaper
  property string password: ""
  property string message: ""
  property bool failed: false
  property bool authRunning: pam.active
  property bool standalone: false
  property string restoreKeyboardName: Quickshell.env("DESKTOP_LOCK_RESTORE_KEYBOARD")
  property int restoreKeyboardIndex: Number(Quickshell.env("DESKTOP_LOCK_RESTORE_INDEX") || 0)
  readonly property string clockText: Qt.formatDateTime(clock.date, "HH:mm")
  readonly property string dateText: Qt.formatDateTime(clock.date, "dddd, MMMM dd")
  property var battery: ({ available: false, capacity: 0, status: "", power: "" })
  property var keyboard: ({ name: "", layout: "", index: 0 })

  signal refocus()

  function parseJson(text, fallback) {
    try {
      return JSON.parse(text);
    } catch (error) {
      console.error("lock: JSON parse failed: " + error);
      return fallback;
    }
  }

  function resetInput() {
    password = "";
    message = "";
    failed = false;
  }

  function keyboardLabel() {
    return shellConfig.keyboardLayoutLabel(keyboard.index);
  }

  function setLockKeyboardLayout(index) {
    const name = String(restoreKeyboardName || "");
    if (name.length > 0)
      lockKeyboardProc.exec([root.backend, "lock-keyboard", "set", name, String(index)]);
  }

  function batteryText() {
    if (!battery.available)
      return "";
    const prefix = battery.status === "Charging" || battery.status === "Full" ? "󰂄 " : "󰁹 ";
    return prefix + String(Math.round(Number(battery.capacity || 0))) + "%";
  }

  function appendPassword(text) {
    if (pam.active || text.length === 0)
      return;
    password += text;
    message = "";
    failed = false;
  }

  function backspacePassword(word) {
    if (pam.active || password.length === 0)
      return;
    password = word ? "" : password.slice(0, -1);
    message = "";
    failed = false;
  }

  function clearPassword() {
    if (pam.active)
      return;
    resetInput();
  }

  function tryUnlock() {
    if (pam.active || password.length === 0)
      return;
    message = "Checking...";
    failed = false;
    pam.start();
  }

  function lock() {
    if (sessionLock.locked) {
      root.refocus();
      return;
    }
    resetInput();
    sessionLock.locked = true;
    refreshProc.running = true;
  }

  function status() {
    return sessionLock.locked;
  }

  function focus() {
    refocus();
  }

  function unlock() {
    setLockKeyboardLayout(restoreKeyboardIndex);
    sessionLock.locked = false;
    if (root.standalone)
      quitTimer.restart();
  }

  Component.onCompleted: {
    refreshProc.running = true;
    if (standalone)
      Qt.callLater(lock);
  }

  Timer {
    interval: 30000
    running: sessionLock.locked
    repeat: true
    onTriggered: refreshProc.running = true
  }

  Timer {
    id: quitTimer
    interval: 120
    repeat: false
    onTriggered: Qt.quit()
  }

  FileView {
    id: wallpaperFile
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

  Process {
    id: refreshProc
    command: [root.backend, "bar", "battery-json"]
    stdout: StdioCollector {
      onStreamFinished: root.battery = root.parseJson(text, root.battery)
    }
    onExited: keyboardProc.running = true
  }

  Process {
    id: keyboardProc
    command: [root.backend, "bar", "keyboard-json"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          root.keyboard = JSON.parse(text);
        } catch (error) {
          root.keyboard = ({ name: "", layout: "", index: 0 });
        }
      }
    }
  }

  Process {
    id: lockKeyboardProc
    onExited: keyboardProc.running = true
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "activelayout") {
        keyboardProc.running = true;
      }
    }
  }

  PamContext {
    id: pam
    config: "desktop-shell-lock"

    onResponseRequiredChanged: {
      if (responseRequired) {
        const reply = root.password;
        root.password = "";
        respond(reply);
      }
    }

    onCompleted: result => {
      if (result === PamResult.Success) {
        root.message = "";
        root.failed = false;
        root.password = "";
        root.unlock();
      } else {
        root.password = "";
        root.failed = true;
        root.message = result === PamResult.MaxTries ? "Too many attempts. Try again later." : "Wrong password";
        root.refocus();
      }
    }

    onError: error => {
      root.password = "";
      root.failed = true;
      root.message = "Authentication error";
      root.refocus();
    }
  }

  IpcHandler {
    target: "screenLock"
    function lock(): void { root.lock(); }
    function status(): bool { return root.status(); }
    function focus(): void { root.focus(); }
  }

  WlSessionLock {
    id: sessionLock
    locked: false

    onLockStateChanged: {
      if (locked) {
        root.resetInput();
        refreshProc.running = true;
        keyboardProc.running = true;
        root.refocus();
      } else {
        root.resetInput();
      }
    }

    WlSessionLockSurface {
      id: surface
      color: theme.bgSolid

      function refocusField() {
        focusRetryTimer.restart();
        lockView.forceInputFocus();
      }

      Timer {
        id: focusRetryTimer
        interval: 80
        repeat: false
        onTriggered: lockView.forceInputFocus()
      }

      Connections {
        target: root
        function onRefocus() {
          surface.refocusField();
        }
      }

      Component.onCompleted: surface.refocusField()

      LockView {
        id: lockView
        anchors.fill: parent
        wallpaperPath: root.wallpaperPath
        clockText: root.clockText
        dateText: root.dateText
        userText: Quickshell.env("USER") || Quickshell.env("LOGNAME")
        keyboardText: root.keyboardLabel()
        batteryVisible: root.battery.available
        batteryText: root.batteryText()
        passwordLength: root.password.length
        message: root.message
        failed: root.failed
        authRunning: root.authRunning

        onAppendText: text => root.appendPassword(text)
        onBackspace: word => root.backspacePassword(word)
        onClear: root.clearPassword()
        onSubmit: root.tryUnlock()
      }
    }
  }
}
