import QtQuick
import Quickshell
import Quickshell.Services.Greetd
import "../common"
import "../lock"

Scope {
  id: root

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
  }

  property string user: Quickshell.env("DESKTOP_SHELL_GREETER_USER")
  property string sessionCommand: Quickshell.env("DESKTOP_SHELL_GREETER_SESSION")
  property string wallpaperPath: Quickshell.env("DESKTOP_SHELL_GREETER_WALLPAPER")
  property string password: ""
  property string pendingResponse: ""
  property string message: Greetd.available ? "" : "Login service unavailable"
  property bool failed: !Greetd.available
  property bool authRunning: false
  property bool awaitingResponse: false
  readonly property string clockText: Qt.formatDateTime(clock.date, "HH:mm")
  readonly property string dateText: Qt.formatDateTime(clock.date, "dddd, MMMM dd")

  function resetInput() {
    password = "";
    pendingResponse = "";
    message = "";
    failed = false;
    authRunning = false;
    awaitingResponse = false;
  }

  function refocus() {
    focusRetry.restart();
    lockView.forceInputFocus();
  }

  function appendPassword(text) {
    if (authRunning || text.length === 0)
      return;
    password += text;
    message = "";
    failed = false;
  }

  function backspacePassword(word) {
    if (authRunning || password.length === 0)
      return;
    password = word ? "" : password.slice(0, -1);
    message = "";
    failed = false;
  }

  function clearPassword() {
    if (authRunning)
      return;
    password = "";
    message = "";
    failed = false;
  }

  function submit() {
    if (!Greetd.available || authRunning || password.length === 0)
      return;

    const reply = password;
    password = "";
    message = "Checking...";
    failed = false;
    authRunning = true;

    if (awaitingResponse) {
      awaitingResponse = false;
      Greetd.respond(reply);
    } else {
      pendingResponse = reply;
      Greetd.createSession(user);
    }
  }

  Connections {
    target: Greetd

    function onAuthMessage(message, error, responseRequired, echoResponse) {
      if (error && message.length > 0)
        root.message = message;

      if (!responseRequired)
        return;

      if (root.pendingResponse.length > 0) {
        const reply = root.pendingResponse;
        root.pendingResponse = "";
        Greetd.respond(reply);
        return;
      }

      root.awaitingResponse = true;
      root.authRunning = false;
      root.message = message.length > 0 ? message : (echoResponse ? "Enter response" : "Enter password");
      root.refocus();
    }

    function onAuthFailure(message) {
      root.resetInput();
      root.failed = true;
      root.message = message.length > 0 ? message : "Wrong password";
      root.refocus();
    }

    function onReadyToLaunch() {
      root.message = "Starting session...";
      Greetd.launch(
        [root.sessionCommand],
        [
          "XDG_SESSION_TYPE=wayland",
          "XDG_CURRENT_DESKTOP=Hyprland",
          "XDG_SESSION_DESKTOP=Hyprland"
        ],
        true
      );
    }

    function onError(error) {
      Qt.quit();
    }
  }

  Timer {
    id: focusRetry
    interval: 80
    repeat: false
    onTriggered: lockView.forceInputFocus()
  }

  FloatingWindow {
    id: window
    visible: true
    color: theme.bgSolid

    Theme {
      id: theme
    }

    Component.onCompleted: root.refocus()

    LockView {
      id: lockView
      anchors.fill: parent
      wallpaperPath: root.wallpaperPath
      clockText: root.clockText
      dateText: root.dateText
      userText: root.user
      keyboardText: "EN"
      batteryVisible: false
      passwordLength: root.password.length
      message: root.message
      failed: root.failed
      authRunning: root.authRunning

      onAppendText: text => root.appendPassword(text)
      onBackspace: word => root.backspacePassword(word)
      onClear: root.clearPassword()
      onSubmit: root.submit()
    }
  }
}
