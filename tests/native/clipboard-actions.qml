import QtQuick
import Quickshell
import Quickshell.Io
import "modules/clipboard_history"

ShellRoot {
  id: suite
  property int step: 0
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
        history.wipe();
        suite.step++;
        break;
      case 2:
        if (actions.text().trim() !== "wipe") return;
        console.log("PASS clipboard actions: close and direct dismissal require fresh wipe confirmation");
        Qt.quit();
      }
    }
  }
  Timer { interval: 5000; running: true; onTriggered: { console.error("FAIL clipboard actions: timed out"); Qt.exit(1); } }
}
