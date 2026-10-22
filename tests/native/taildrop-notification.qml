import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import "TailscaleStatus.js" as Status

// Run on a private session bus: exercise the real sender/receiver protocol
// without posting a test notification to the user's desktop.
ShellRoot {
  id: suite
  property bool received: false
  function verify(condition, message) {
    if (!condition) { console.error("FAIL taildrop notification: " + message); Qt.exit(1); }
  }
  NotificationServer {
    id: server
    bodyMarkupSupported: true
    persistenceSupported: true
    onNotification: notification => {
      suite.verify(notification.appName === "Tailscale", "wrong application name");
      suite.verify(notification.summary === "2 files received", "wrong summary");
      suite.verify(notification.body === "&lt;file&gt;&amp;.txt<br/>notes.md", "unsafe or altered filenames");
      suite.verify(!notification.transient, "notification would bypass history");
      suite.verify(Number(notification.urgency) === 1, "notification would bypass normal urgency policy");
      notification.tracked = true;
      suite.received = true;
      finish.restart();
    }
  }
  Timer {
    interval: 100; running: true
    onTriggered: Quickshell.execDetached(Status.receivedNotification([{name:"<file>&.txt",size:1},{name:"notes.md",size:2}], ""))
  }
  Timer {
    id: finish; interval: 100
    onTriggered: {
      suite.verify(suite.received && server.trackedNotifications.values.length === 1, "notification was not retained");
      console.log("PASS taildrop notification: real freedesktop delivery, literal filenames, normal urgency and history eligibility");
      Qt.quit();
    }
  }
  Timer { interval: 5000; running: true; onTriggered: { console.error("FAIL taildrop notification: timed out"); Qt.exit(1); } }
}
