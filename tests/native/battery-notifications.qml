import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import "."

// Exercise real libnotify delivery without changing the user's battery or bus.
ShellRoot {
  id: suite
  property int received: 0
  property int closed: 0
  property bool expectCritical: false
  property int step: 0

  function verify(condition, message) {
    if (!condition) { console.error("FAIL battery notifications: " + message); Qt.exit(1); }
  }

  function sample(capacity, status = "Discharging", available = true) {
    warnings.data = {available: available, capacity: capacity, status: status};
  }

  BatteryNotifications {
    id: warnings
    onDismissRequested: id => {
      const notification = server.trackedNotifications.values.find(item => Number(item.id) === id);
      suite.verify(Boolean(notification), "dismissal lost its notification");
      notification.dismiss();
    }
  }

  NotificationServer {
    id: server
    persistenceSupported: true
    onNotification: notification => {
      notification.tracked = true;
      suite.received++;
      suite.verify(notification.appName === "Battery", "wrong application name");
      suite.verify(notification.summary === (suite.expectCritical ? "Battery critically low" : "Battery low"), "wrong summary");
      suite.verify(notification.body === warnings.data.capacity + "% remaining. Connect a charger.", "wrong capacity");
      suite.verify(Number(notification.urgency) === (suite.expectCritical ? 2 : 0), "wrong urgency");
      suite.verify(notification.hints["suppress-sound"] === !suite.expectCritical, "wrong sound policy");
      suite.verify(notification.hints["x-desktop-shell-bypass-dnd"] !== true, "warning bypasses DND");
      suite.verify(notification.resident === suite.expectCritical, "wrong persistence policy");
      suite.verify(notification.expireTimeout === (suite.expectCritical ? 0 : -1), "wrong expiration");
      suite.verify(!notification.transient, "warning would bypass history");
      notification.closed.connect(() => suite.closed++);
    }
  }

  Timer {
    interval: 120; running: true; repeat: true
    onTriggered: {
      switch (suite.step++) {
      case 0: suite.sample(60); break;
      case 1:
        suite.verify(suite.received === 0, "healthy battery warned");
        suite.sample(30); break;
      case 2:
        suite.verify(suite.received === 1, "missing yellow warning");
        suite.sample(29); suite.sample(31); suite.sample(30); break;
      case 3:
        suite.verify(suite.received === 1, "yellow threshold jitter repeated warning");
        suite.expectCritical = true; suite.sample(15); break;
      case 4:
        suite.verify(suite.received === 2 && suite.closed === 1, "red did not replace yellow");
        suite.sample(14); suite.sample(16); suite.sample(15); break;
      case 5:
        suite.verify(suite.received === 2, "red threshold jitter repeated warning");
        suite.sample(15, "Charging"); break;
      case 6:
        suite.verify(suite.closed === 2, "charging left a stale warning");
        suite.sample(8); break;
      case 7:
        suite.verify(suite.received === 3, "starting red did not warn once");
        suite.sample(0, "", false); break;
      case 8:
        suite.verify(suite.closed === 3, "battery removal left a stale warning");
        suite.expectCritical = false; suite.sample(25); break;
      case 9:
        suite.verify(suite.received === 4, "starting yellow did not warn");
        suite.sample(100, "Full"); break;
      case 10:
        suite.verify(suite.closed === 4, "full battery left a stale warning");
        suite.sample(0, "Unknown"); break;
      case 11:
        suite.verify(suite.received === 4, "unknown state warned");
        suite.sample(30);
        // Recover before notify-send returns its ID; that late ID must close.
        suite.sample(30, "Charging"); break;
      case 12:
        suite.verify(suite.received === 5 && suite.closed === 5, "late delivery survived recovery");
        suite.verify(server.trackedNotifications.values.length === 0, "stale warnings remain");
        console.log("PASS battery notifications: real yellow/red delivery, sound/persistence hints, cycle latching, startup, recovery and late delivery");
        Qt.quit();
      }
    }
  }
  Timer { interval: 5000; running: true; onTriggered: { console.error("FAIL battery notifications: timed out"); Qt.exit(1); } }
}
