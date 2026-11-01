import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import "modules/bar"

ShellRoot {
  id: suite
  property int step: 0
  property real widthWithoutProfiles: 0
  property string requestedProfileProvider: ""
  readonly property var control: network.controls[0] || null
  readonly property var current: network.status(control)
  NetworkState {
    id: network
    backend: Quickshell.env("DESKTOP_SHELL_TEST_BACKEND")
    configPath: Quickshell.env("DESKTOP_SHELL_TEST_CONFIG")
  }
  Window {
    visible: true
    width: 320
    height: 50
    RowLayout {
      anchors.fill: parent
      NetworkControls {
        id: barControls
        controller: network
        itemPadding: 8
        itemGap: 8
        contentGap: 6
        onProfilesRequested: controlId => suite.requestedProfileProvider = controlId
      }
      Item { Layout.fillWidth: true }
    }
  }
  function findArrow(item) {
    if (item.Accessible?.name === "Private profiles") return item;
    for (const child of item.children || []) {
      const match = findArrow(child);
      if (match) return match;
    }
    return null;
  }
  function verify(condition, message) {
    if (!condition) { console.error("FAIL network profiles: " + message); Qt.exit(1); }
  }
  Timer {
    interval: 100; running: true; repeat: true
    onTriggered: {
      if (suite.step === 0) {
        if (suite.current.selectedProfile !== "north") {
          if (suite.control) suite.widthWithoutProfiles = barControls.fullWidth;
          return;
        }
        suite.verify(network.profiles(suite.control).length === 2, "missing generic profiles");
        const arrow = suite.findArrow(barControls);
        suite.verify(arrow?.visible && arrow.width > 0 && arrow.height > 0,
          "profile arrow missing from real bar control");
        suite.verify(suite.widthWithoutProfiles > 0 && barControls.fullWidth > suite.widthWithoutProfiles,
          "bar width did not grow when profiles arrived");
        arrow.clicked();
        suite.verify(suite.requestedProfileProvider === "private" && !suite.current.busy,
          "profile arrow failed to route the provider ID or toggled the connection");
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
        console.log("PASS network profiles: bar arrow, layout, routing, stale reads, serialization and retry");
        Qt.quit();
      }
      suite.step++;
    }
  }
  Timer { interval: 7000; running: true; onTriggered: { console.error("FAIL network profiles: timeout"); Qt.exit(1); } }
}
