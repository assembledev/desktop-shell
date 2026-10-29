import QtQuick
import Quickshell
import Quickshell.Io
import "modules/clipboard_history"

ShellRoot {
  id: suite
  property int step: 0
  property int lastGeneration: 0
  property string workingBackend: ""
  ClipboardHistory { id: history }
  FileView {
    id: actions
    path: Quickshell.env("TEST_ACTION_LOG")
    preload: true
    watchChanges: true
    onFileChanged: reload()
  }
  function verify(condition, message) {
    if (!condition) { console.error("FAIL clipboard actions: " + message); Qt.exit(1); }
  }
  function generation() { return Number(history.entries[0]?.generation || 0); }
  function item(record) { return {record: record, entryId: "fixture", kind: "text"}; }
  Timer {
    interval: 50; running: true; repeat: true
    onTriggered: {
      if (!history.hydrated) return;
      switch (suite.step) {
      case 0:
        history.open = true;
        history.wipe();
        suite.verify(history.wipeArmed, "first wipe request did not ask for confirmation");
        history.closePicker();
        history.open = true;
        history.wipe();
        suite.verify(history.wipeArmed, "close/reopen retained the previous wipe confirmation");
        suite.step++;
        break;
      case 1:
        suite.verify(actions.text().trim() === "", "reopening allowed an unconfirmed wipe");
        history.open = false;
        history.open = true;
        history.wipe();
        suite.verify(history.wipeArmed, "direct dismissal retained wipe confirmation");
        suite.lastGeneration = suite.generation();
        history.wipe();
        suite.step++;
        break;
      case 2:
        if (suite.generation() <= suite.lastGeneration) return;
        history.previewPaths = {fixture: Quickshell.env("TEST_PREVIEW_PATH")};
        suite.lastGeneration = suite.generation();
        history.deleteItem(suite.item("failed"));
        history.deleteItem(suite.item("ignored"));
        history.copyItem(suite.item("ignored"));
        history.wipe();
        suite.step++;
        break;
      case 3:
        if (suite.generation() <= suite.lastGeneration) return;
        suite.verify(history.message === "Failed to delete clipboard entry", "successful list refresh erased the deletion error");
        suite.lastGeneration = suite.generation();
        history.refresh(false);
        suite.step++;
        break;
      case 4:
        if (suite.generation() <= suite.lastGeneration) return;
        suite.verify(history.message === "Failed to delete clipboard entry", "manual refresh erased the deletion error");
        suite.lastGeneration = suite.generation();
        history.deleteItem(suite.item("good"));
        suite.step++;
        break;
      case 5:
        if (suite.generation() <= suite.lastGeneration) return;
        suite.verify(history.message === "", "successful retry retained the old error");
        suite.lastGeneration = suite.generation();
        history.wipe();
        history.wipe();
        history.deleteItem(suite.item("ignored"));
        history.wipe();
        suite.step++;
        break;
      case 6:
        if (suite.generation() <= suite.lastGeneration) return;
        suite.verify(history.message === "Failed to wipe clipboard history", "crashed wipe was not reported");
        suite.verify(history.previewPaths.fixture === Quickshell.env("TEST_PREVIEW_PATH"), "failed wipe discarded preview state");
        suite.workingBackend = history.backend;
        history.backend = suite.workingBackend + "-missing";
        history.deleteItem(suite.item("missing"));
        history.wipe();
        suite.step++;
        break;
      case 7:
        if (history.message !== "Failed to delete clipboard entry") return;
        suite.verify(!history.actionRunning, "missing backend left actions disabled");
        history.backend = suite.workingBackend;
        suite.lastGeneration = suite.generation();
        history.deleteItem(suite.item("recovered"));
        suite.step++;
        break;
      case 8:
        if (suite.generation() <= suite.lastGeneration) return;
        suite.verify(history.message === "", "missing-backend recovery retained the error");
        console.log("PASS clipboard actions: confirmation lifetime, delete/wipe failures, refresh, overlaps and missing-backend recovery");
        Qt.quit();
      }
    }
  }
  Timer { interval: 5000; running: true; onTriggered: { console.error("FAIL clipboard actions: timed out at step " + suite.step); Qt.exit(1); } }
}
