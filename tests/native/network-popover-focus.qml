import QtQuick
import Quickshell
import "modules/network"

// Exercise the real popover and shared overlay in a Wayland session.
// Fixture state keeps device commands and external probes out of the test.
ShellRoot {
  id: suite
  property int step: 0
  readonly property var overlay: details.surface

  QtObject {
    id: bar
    property int height: 37
  }
  QtObject {
    id: fakeModel
    property bool detailsActive: false
    property bool connected: false
    property var data: ({ available: true })
    property string icon: "wifi"
    property string ssid: ""
    property string security: ""
    property var signalStrength: null
    property var receiveRate: null
    property var transmitRate: null
    property var ping: ({ state: "idle", milliseconds: null })
    property var publicIp: ({ state: "idle", address: "" })
    function snapshot() { return ({}); }
  }
  NetworkDetails { id: details; model: fakeModel; barSurface: bar }

  function verify(condition, message) {
    if (condition)
      return;
    console.error("FAIL network popover: " + message);
    Qt.exit(1);
  }

  Timer {
    interval: 50
    running: true
    repeat: true
    onTriggered: {
      if (suite.step === 0) {
        if (Quickshell.screens.length === 0)
          return;
        suite.verify(suite.overlay, "missing overlay");
        details.toggleDetails(Quickshell.screens[0]);
      } else if (suite.step === 1) {
        suite.verify(details.open && !suite.overlay.keyboardRequested, "bar opening must preserve pointer focus");
        details.toggleDetails(Quickshell.screens[0]);
      } else if (suite.step === 2) {
        suite.verify(!details.open && !suite.overlay.keyboardRequested, "second bar activation must close");
        details.openDetails();
      } else if (suite.step === 3) {
        suite.verify(details.open && suite.overlay.keyboardRequested, "keyboard opening must request focus");
        details.closeDetails();
      } else if (suite.step === 4) {
        suite.verify(!details.open && !suite.overlay.keyboardRequested, "closing must release keyboard focus");
        details.toggleDetails(Quickshell.screens[0]);
      } else if (suite.step === 5) {
        suite.verify(details.open && !suite.overlay.keyboardRequested, "bar reopen must not inherit keyboard focus");
        details.toggleDetails(Quickshell.screens[0]);
      } else {
        suite.verify(!details.open && !fakeModel.detailsActive, "closing must stop details");
        console.log("PASS network popover: pointer toggle, keyboard focus and reopen");
        Qt.quit();
      }
      suite.step++;
    }
  }
  Timer { interval: 5000; running: true; onTriggered: { console.error("FAIL network popover: timed out"); Qt.exit(1); } }
}
