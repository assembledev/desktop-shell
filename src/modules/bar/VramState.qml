import QtQuick
import Quickshell
import Quickshell.Io

Scope {
  id: root
  property string backend: Quickshell.env("DESKTOP_SHELL_BACKEND")
  property bool active: false
  property int interval: 30000
  property var data: ({ hasVram: false, vram: 0, vramText: "--" })
  property string output: ""

  function refresh() {
    if (root.active && !collector.running) collector.running = true;
  }
  function clear() { root.data = { hasVram: false, vram: 0, vramText: "--" }; }

  onActiveChanged: {
    if (active) Qt.callLater(root.refresh);
    // Let an already bounded query finish. A quick hide/show reuses that
    // request instead of leaving a subprocess behind and starting another.
    else root.clear();
  }
  Component.onCompleted: Qt.callLater(root.refresh)

  Timer {
    interval: root.interval
    running: root.active
    repeat: true
    onTriggered: root.refresh()
  }
  Process {
    id: collector
    command: [root.backend, "bar", "vram-json"]
    onStarted: root.output = ""
    stdout: StdioCollector { onStreamFinished: root.output = text }
    onExited: function(code) {
      if (!root.active) return;
      try {
        const next = code === 0 ? JSON.parse(root.output) : null;
        if (next && typeof next.hasVram === "boolean" && Number.isFinite(next.vram)
            && typeof next.vramText === "string") root.data = next;
        else root.clear();
      } catch (error) { root.clear(); }
    }
  }
}
