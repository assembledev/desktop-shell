import QtQuick
import Quickshell
import "modules/tailscale"

ShellRoot {
  id: suite
  property int step: 0
  property bool waiting: false
  property bool expectOpen: false
  property bool appendedDuringSave: false
  readonly property var names: ["readme.md", "archive.tar.gz", "cancelled.txt", "résumé #%20 [draft].tar.gz", "batch-one.tar.gz", "batch-two.md", "cancel-batch.txt", "skip-batch.md", "queued-first.txt", "queued-second.md", "running-first.txt", "running-second.md", "inbox-one.txt", "inbox-two.md", "arrived-later.txt", "failed.txt", "after-failure.md", "cancel-appended.txt", "discard-appended.md"]
  readonly property var completedCounts: [1, 2, 2, 3, 5, 5, 7, 9, 11, 12, 12]
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
    property var data: ({available:true,connected:true,files:[],peers:[]})
    function refresh() {}
    function refreshInbox() { completed++; }
    function snapshot() { return data; }
  }
  QtObject { id: controller; property var controls: [] }
  TailscaleDetails { id: details; model: model; networkController: controller; barSurface: bar }
  function verify(condition, message) {
    if (!condition) { console.error("FAIL taildrop save: " + message); Qt.exit(1); }
  }
  function files(names) { return names.map(name => ({name:name,size:1})); }
  function findButton(item, label) {
    if (item.label === label && typeof item.clicked === "function") return item;
    for (const child of item.children || []) {
      const match = findButton(child, label);
      if (match) return match;
    }
    return null;
  }
  Timer {
    interval: 50; running: true; repeat: true
    onTriggered: {
      if (suite.waiting) {
        suite.verify(details.open === suite.expectOpen && model.detailsActive === suite.expectOpen, "Save changed overlay navigation");
        if (suite.step === 7 && !suite.appendedDuringSave && !details.dialogOpen && details.receivingName === suite.names[10]) {
          suite.appendedDuringSave = true;
          details.saveReceived(suite.files([suite.names[10], suite.names[11]]));
        }
        if (!details.dialogOpen && details.receiveQueue.length === 0 && model.completed >= suite.completedCounts[suite.step]) {
          suite.verify(details.error === (suite.step === 9 ? "Synthetic save failure" : ""), details.error);
          suite.waiting = false;
          suite.step++;
        }
        return;
      }
      if (suite.step === suite.completedCounts.length) {
        suite.verify(suite.appendedDuringSave, "did not exercise queuing during a running download");
        details.open = false;
        details.saveReceived([{name:"gone.txt",size:1}]);
        suite.verify(!details.dialogOpen && details.receiveQueue.length === 0 && !details.open && details.error.length > 0, "stale notification opened a chooser or overlay");
        console.log("PASS taildrop save: shared inbox/notification queue, busy requests, deduplication, snapshots, cancellation, failures and literal filenames");
        Qt.quit();
        return;
      }
      suite.waiting = true;
      suite.expectOpen = suite.step === 0 || suite.step === 3 || suite.step === 8;
      details.open = suite.expectOpen;
      details.page = "received";
      model.data = Object.assign({}, model.data, {files:suite.files(suite.names)});
      if (suite.step === 0) {
        suite.findButton(details.surface.contentItem, "Save…").clicked();
      } else if (suite.step < 4) {
        details.saveReceived(suite.files([suite.names[suite.step]]), !suite.expectOpen);
      } else if (suite.step === 4 || suite.step === 5) {
        details.saveReceived(suite.files(suite.names.slice(suite.step === 4 ? 4 : 6, suite.step === 4 ? 6 : 8)));
      } else if (suite.step === 6) {
        details.saveReceived(suite.files([suite.names[8]]));
        details.saveReceived(suite.files([suite.names[8], suite.names[9], suite.names[9]]));
        suite.verify(details.receiveQueue.length === 2, "busy Save was discarded or duplicated");
      } else if (suite.step === 7) {
        details.saveReceived(suite.files([suite.names[10]]));
      } else if (suite.step === 8) {
        model.data = Object.assign({}, model.data, {files:suite.files(suite.names.slice(12, 14))});
        const saveAll = suite.findButton(details.surface.contentItem, "Save all");
        suite.verify(saveAll !== null, "inbox has no batch save action");
        saveAll.clicked();
        model.data = Object.assign({}, model.data, {files:suite.files(suite.names.slice(12, 15))});
        suite.verify(details.receiveQueue.length === 2, "Save all did not snapshot the waiting inbox");
      } else if (suite.step === 9) {
        details.saveReceived(suite.files(suite.names.slice(15, 17)));
      } else {
        details.saveReceived(suite.files([suite.names[17]]));
        details.saveReceived(suite.files([suite.names[18]]));
      }
      const name = details.receivingName;
      details.chooseDestination("overlapping-request.txt");
      suite.verify(details.receivingName === name, "overlapping request retargeted the save");
    }
  }
  Timer { interval: 10000; running: true; onTriggered: { console.error("FAIL taildrop save: timeout at step " + suite.step); Qt.exit(1); } }
}
