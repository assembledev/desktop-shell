import QtQuick
import Quickshell
import "modules/tailscale"

ShellRoot {
  id: suite
  property int step: 0
  property bool waiting: false
  readonly property var names: ["readme.md", "archive.tar.gz", "cancelled.txt", "résumé #%20 [draft].tar.gz"]
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
    property var data: ({available:true,connected:true,files:suite.names.map(name => ({name:name,size:1})),peers:[]})
    function refresh() {}
    function refreshInbox() { suite.waiting = false; suite.step++; }
    function snapshot() { return data; }
  }
  QtObject { id: controller; property var controls: [] }
  TailscaleDetails { id: details; model: model; networkController: controller; barSurface: bar }
  Timer {
    interval: 100; running: true; repeat: true
    onTriggered: {
      if (suite.waiting) {
        if (suite.step === 2 && !details.dialogOpen) { suite.waiting = false; suite.step++; }
        return;
      }
      if (suite.step === suite.names.length) {
        if (details.error.length > 0) { console.error(details.error); Qt.exit(1); return; }
        details.saveReceived([{name:"gone.txt",size:1}]);
        if (details.dialogOpen || details.error.length === 0) { console.error("Stale notification opened a save chooser"); Qt.exit(1); return; }
        details.saveReceived(model.data.files);
        if (details.page !== "received" || details.dialogOpen) { console.error("Batch Save did not open the received-file list"); Qt.exit(1); return; }
        console.log("PASS taildrop save: consecutive saves, notification actions, cancellation and literal filenames");
        Qt.quit();
        return;
      }
      suite.waiting = true;
      if (suite.step === 1) details.saveReceived([{name:suite.names[suite.step],size:1}]);
      else details.chooseDestination(suite.names[suite.step]);
      details.chooseDestination("overlapping-request.txt");
      if (details.receivingName !== suite.names[suite.step]) { console.error("Overlapping request retargeted the save"); Qt.exit(1); }
    }
  }
  Timer { interval: 7000; running: true; onTriggered: { console.error("FAIL taildrop save: timeout"); Qt.exit(1); } }
}
