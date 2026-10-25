pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "BatteryStatus.js" as BatteryStatus

Scope {
  id: root

  property var data: ({ available: false })
  property int announcedLevel: 0
  property int notificationId: 0
  property int generation: 0
  signal dismissRequested(int id)

  function dismissCurrent() {
    if (notificationId > 0)
      dismissRequested(notificationId);
    notificationId = 0;
  }

  function update() {
    if (!data.available || BatteryStatus.externallyPowered(data)) {
      announcedLevel = 0;
      generation++;
      dismissCurrent();
      return;
    }
    if (data.status !== "Discharging")
      return;

    const severity = BatteryStatus.severity(data);
    const level = severity === "critical" ? 2 : severity === "low" ? 1 : 0;
    // Latch each level until charging, so threshold jitter cannot repeat alerts.
    if (level <= announcedLevel)
      return;

    const previousLevel = announcedLevel;
    announcedLevel = level;
    generation++;
    dismissCurrent();
    const critical = level === 2;
    const process = sender.createObject(root, {
      generation: root.generation,
      previousLevel: previousLevel,
      command: [
        "notify-send", "--print-id", "--app-name=Battery",
        "--icon=" + (critical ? "battery-caution" : "battery-low"),
        "--urgency=" + (critical ? "critical" : "low"),
        "--expire-time=" + (critical ? "0" : "-1"),
        "--hint=boolean:resident:" + critical,
        "--hint=boolean:suppress-sound:" + !critical,
        "--", critical ? "Battery critically low" : "Battery low",
        BatteryStatus.capacity(data) + "% remaining. Connect a charger."
      ]
    });
    process.running = true;
  }

  onDataChanged: update()
  Component.onCompleted: update()

  Component {
    id: sender
    Process {
      id: notification
      required property int generation
      required property int previousLevel
      stdout: StdioCollector { id: output }
      onExited: function(code) {
        const id = Number(output.text.trim());
        if (code === 0 && id > 0) {
          // Charging or a newer warning may arrive before notify-send exits.
          if (generation === root.generation)
            root.notificationId = id;
          else
            root.dismissRequested(id);
        } else if (generation === root.generation) {
          root.announcedLevel = previousLevel;
          console.warn("battery: could not send notification");
        }
        notification.destroy();
      }
    }
  }
}
