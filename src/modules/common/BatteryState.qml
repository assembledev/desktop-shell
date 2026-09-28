import QtQuick
import Quickshell
import Quickshell.Io
import "BatteryStatus.js" as BatteryStatus

Scope {
  id: root

  property string backend: Quickshell.env("DESKTOP_SHELL_BACKEND")
  property bool active: true
  property var data: ({ available: false, capacity: 0, status: "", power: "" })
  readonly property bool available: Boolean(data.available)
  readonly property string icon: BatteryStatus.icon(data)
  readonly property string label: BatteryStatus.capacity(data) + "%"
  readonly property string severity: BatteryStatus.severity(data)

  function refresh() {
    if (active)
      sample.running = true;
  }

  Timer {
    interval: 30000
    running: root.active
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Process {
    id: sample
    command: [root.backend, "bar", "battery-json"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const next = JSON.parse(text);
          if (next && typeof next.available === "boolean")
            root.data = next;
        } catch (error) {
          console.warn("battery: invalid sample: " + error);
        }
      }
    }
  }
}
