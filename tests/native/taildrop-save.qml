import QtQuick
import Quickshell
import "modules/tailscale"

ShellRoot {
  id: suite
  property int step: 0
  property bool waiting: false
  readonly property var names: ["readme.md", "archive.tar.gz", "cancelled.txt", "résumé #%20 [draft].tar.gz", "batch-one.tar.gz", "batch-two.md", "cancel-batch.txt", "skip-batch.md"]
  readonly property var completedCounts: [1, 2, 2, 3, 5, 5]
  QtObject { id: bar; property int height: 37 }
  QtObject {
    id: model
    property string backend: Quickshell.env("DESKTOP_SHELL_TEST_BACKEND")
    property bool detailsActive: false
    property bool connected: true
    property bool fresh: true
    property double now: Date.now()
    property string selectedId: ""
    property var selected: null
    property var online: []
    property var offline: []
    property bool canSend: false
    property string connectionText: ""
    property string pingText: ""
    property int completed: 0
    property var data: ({available:true,connected:true,files:suite.names.map(name => ({name:name,size:1})),peers:[]})
    function refresh() {}
    function refreshInbox() { completed++; }
    function snapshot() { return data; }
  }
  QtObject { id: controller; property var controls: [] }
  TailscaleDetails { id: details; model: model; networkController: controller; barSurface: bar }
  function verify(condition, message) {
    if (!condition) { console.error("FAIL taildrop save: " + message); Qt.exit(1); }
  }
  Connections {
    target: details
    function onOpenChanged() { suite.verify(!details.open, "notification Save opened the Tailscale overlay"); }
  }
  Timer {
    interval: 100; running: true; repeat: true
    onTriggered: {
      if (suite.waiting) {
        suite.verify(!details.open && !model.detailsActive, "notification Save activated the overlay");
        if (!details.dialogOpen && !details.savingFromNotification && model.completed >= suite.completedCounts[suite.step]) {
          suite.waiting = false;
          suite.step++;
        }
        return;
      }
      if (suite.step === suite.completedCounts.length) {
        suite.verify(details.error.length === 0, details.error);
        details.saveReceived([{name:"gone.txt",size:1}]);
        suite.verify(!details.dialogOpen && !details.open && details.error.length > 0, "stale notification opened a chooser or overlay");
        console.log("PASS taildrop save: direct notification choosers, batches, cancellation and literal filenames");
        Qt.quit();
        return;
      }
      suite.waiting = true;
      if (suite.step === 0 || suite.step === 3) details.chooseDestination(suite.names[suite.step]);
      else if (suite.step < 3) details.saveReceived([{name:suite.names[suite.step],size:1}]);
      else details.saveReceived(suite.names.slice(suite.step === 4 ? 4 : 6, suite.step === 4 ? 6 : 8).map(name => ({name:name,size:1})));
      const name = details.receivingName;
      details.chooseDestination("overlapping-request.txt");
      suite.verify(details.receivingName === name, "overlapping request retargeted the save");
    }
  }
  Timer { interval: 7000; running: true; onTriggered: { console.error("FAIL taildrop save: timeout"); Qt.exit(1); } }
}
