import QtQuick
import Quickshell
import Quickshell.Io
import "RamStatus.js" as RamStatus

Scope {
  id: root
  property bool active: false
  property string path: (Quickshell.env("DESKTOP_SHELL_PROC_ROOT") || "/proc") + "/meminfo"
  property int interval: 5000
  property var data: RamStatus.unavailable()

  function refresh() {
    if (root.active) memoryFile.reload();
  }

  onActiveChanged: if (!active) root.data = RamStatus.unavailable()

  FileView {
    id: memoryFile
    path: root.active ? root.path : ""
    preload: true
    blockLoading: false
    blockAllReads: false
    watchChanges: false
    onLoaded: if (root.active) root.data = RamStatus.parse(text())
    onLoadFailed: root.data = RamStatus.unavailable()
  }
  Timer {
    interval: root.interval
    running: root.active
    repeat: true
    onTriggered: root.refresh()
  }
}
