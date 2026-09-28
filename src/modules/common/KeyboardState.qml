import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Scope {
  id: root

  property string backend: Quickshell.env("DESKTOP_SHELL_BACKEND")
  property var data: ({ name: "", layout: "", index: -1 })
  readonly property string label: Number(data.index) >= 0
    ? config.keyboardLayoutLabel(data.index) : "--"
  property bool refreshPending: false

  ShellConfig { id: config }

  function refresh() {
    if (sample.running)
      refreshPending = true;
    else
      sample.running = true;
  }

  Timer {
    interval: 300000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "activelayout")
        root.refresh();
    }
  }

  Process {
    id: sample
    command: [root.backend, "bar", "keyboard-json"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const next = JSON.parse(text);
          root.data = next && Number.isInteger(next.index) ? next : ({ index: -1 });
        } catch (error) {
          root.data = ({ index: -1 });
        }
      }
    }
    onExited: {
      if (root.refreshPending) {
        root.refreshPending = false;
        root.refresh();
      }
    }
  }
}
