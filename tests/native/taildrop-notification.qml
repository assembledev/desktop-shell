import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import "."

// Run on a private session bus: exercise the real sender/receiver protocol
// without posting a test notification to the user's desktop.
ShellRoot {
  id: suite
  property bool received: false
  property bool saved: false
  TaildropNotifications {
    id: notifications
    onSaveRequested: files => {
      suite.verify(files.length === 2 && files[0].name === "<file>&.txt" && files[1].name === "notes.md", "Save lost its notification files");
      suite.saved = true;
    }
  }
  function verify(condition, message) {
    if (!condition) { console.error("FAIL taildrop notification: " + message); Qt.exit(1); }
  }
  NotificationServer {
    id: server
    bodyMarkupSupported: true
    persistenceSupported: true
    actionsSupported: true
    onNotification: notification => {
      suite.verify(notification.appName === "Tailscale", "wrong application name");
      suite.verify(notification.summary === "2 files received", "wrong summary");
      suite.verify(notification.body === "&lt;file&gt;&amp;.txt<br/>notes.md", "unsafe or altered filenames");
      suite.verify(!notification.transient, "notification would bypass history");
      suite.verify(Number(notification.urgency) === 1, "notification would bypass normal urgency policy");
      notification.tracked = true;
      suite.received = true;
      suite.verify(notification.actions.length === 1 && notification.actions[0].identifier === "save" && notification.actions[0].text === "Save", "missing matching Save action");
      Qt.callLater(() => {
        suite.verify(server.trackedNotifications.values.length === 1, "notification was not retained");
        notification.actions[0].invoke();
      });
      finish.restart();
    }
  }
  Timer {
    interval: 100; running: true
    onTriggered: notifications.notify([{name:"<file>&.txt",size:1},{name:"notes.md",size:2}], "")
  }
  Timer {
    id: finish; interval: 100; repeat: true
    onTriggered: {
      if (!suite.saved) return;
      suite.verify(suite.received, "notification was not delivered");
      console.log("PASS taildrop notification: real delivery and Save action with literal filenames and normal notification policy");
      Qt.quit();
    }
  }
  Timer { interval: 5000; running: true; onTriggered: { console.error("FAIL taildrop notification: timed out"); Qt.exit(1); } }
}
