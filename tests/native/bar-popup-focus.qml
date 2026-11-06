import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "modules/common"

ShellRoot {
  id: suite
  property bool opened: false
  property bool retained: false
  property bool suspended: false
  property int triggerClicks: 0
  property int otherClicks: 0
  property int dismissals: 0
  function show(keyboard) {
    popup.keyboardRequested = keyboard;
    opened = true;
    if (keyboard) Qt.callLater(() => editor.forceActiveFocus());
  }
  function close() { opened = false; }
  PanelWindow {
    id: bar
    screen: Quickshell.screens.find(s => s.name === "focus-primary")
    anchors { top: true; left: true; right: true }
    implicitHeight: 37
    color: "#202030"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    readonly property var popupPeers: [bar, otherBar]
    MouseArea {
      id: trigger
      x: 100; width: 60; height: parent.height
      hoverEnabled: true
      onClicked: { suite.triggerClicks++; if (suite.opened) suite.close(); else suite.show(false); }
    }
  }
  PanelWindow {
    id: otherBar
    screen: Quickshell.screens.find(s => s.name === "focus-test")
    anchors { top: true; left: true; right: true }
    implicitHeight: 37
    color: "#302020"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    MouseArea { anchors.fill: parent; onClicked: suite.otherClicks++ }
  }
  FloatingWindow {
    id: application
    visible: true
    title: "popup-test-application"
    implicitWidth: 400; implicitHeight: 250
    TextField { id: appEditor; anchors.fill: parent; focus: true }
  }
  FloatingWindow {
    visible: suite.suspended
    title: "popup-test-chooser"
    implicitWidth: 300; implicitHeight: 200
    TextField { id: chooserEditor; anchors.fill: parent; focus: true }
  }
  BarOverlayWindow {
    id: popup
    barSurface: bar
    requested: suite.opened
    presented: suite.opened || suite.retained
    suspended: suite.suspended
    surfaceNamespace: "popup-test"
    popupContent: card
    onDismissRequested: { suite.dismissals++; suite.close(); }
    MouseArea { anchors.fill: parent; onClicked: { suite.dismissals++; suite.close(); } }
    Rectangle {
      id: card
      x: 100; y: 2; width: 300; height: 240
      color: "#303040"
      TextField { id: editor; anchors.fill: parent; anchors.margins: 20; focus: true }
      Shortcut { sequence: "Esc"; enabled: suite.opened; onActivated: suite.close() }
    }
  }
  IpcHandler {
    target: "test"
    function open(keyboard: bool): void { suite.show(keyboard); }
    function close(): void { suite.close(); }
    function retain(value: bool): void { suite.retained = value; }
    function suspend(value: bool): void { suite.suspended = value; }
    function snapshot(): string {
      return JSON.stringify({opened:suite.opened, grab:popup.nativeGrabActive,
        keyboard:popup.keyboardRequested, ready:popup.keyboardReady, active:editor.Window.active, chooserActive:chooserEditor.Window.active,
        hover:trigger.containsMouse, clicks:suite.triggerClicks, other:suite.otherClicks,
        dismissals:suite.dismissals, text:editor.text, appText:appEditor.text,
        chooserText:chooserEditor.text, presented:popup.backingWindowVisible});
    }
  }
}
