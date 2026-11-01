import QtQuick
import Quickshell
import "modules/bar"

ShellRoot {
  id: suite
  property int step: 0
  readonly property var control: network.controls[0] || null
  readonly property var current: network.status(control)
  NetworkState {
    id: network
    backend: Quickshell.env("DESKTOP_SHELL_TEST_BACKEND")
    configPath: Quickshell.env("DESKTOP_SHELL_TEST_CONFIG")
  }
  function verify(condition, message) {
    if (!condition) { console.error("FAIL network profiles: " + message); Qt.exit(1); }
  }
  Timer {
    interval: 100; running: true; repeat: true
    onTriggered: {
      if (suite.step === 0) {
        if (suite.current.selectedProfile !== "north") return;
        suite.verify(network.profiles(suite.control).length === 2, "missing generic profiles");
        network.statusRequested(suite.control.id);
      } else if (suite.step === 1) {
        network.selectProfile(suite.control, "south");
        network.activate(suite.control);
        suite.verify(suite.current.busy, "selection did not serialize toggle");
      } else if (suite.step === 2) {
        if (suite.current.busy) return;
        suite.verify(suite.current.selectedProfile === "south", "failed selection was not reconciled or stale status won");
        suite.verify(!suite.current.active, "selection fabricated connection state");
        suite.verify(suite.current.error.includes("fixture selection failed"), "reconciliation lost command error");
        network.selectProfile(suite.control, "south");
      } else {
        if (suite.current.busy) return;
        suite.verify(suite.current.selectedProfile === "south" && !suite.current.error, "same-profile retry failed");
        console.log("PASS network profiles: stale reads, serialization, failed selection reconciliation and retry");
        Qt.quit();
      }
      suite.step++;
    }
  }
  Timer { interval: 7000; running: true; onTriggered: { console.error("FAIL network profiles: timeout"); Qt.exit(1); } }
}
