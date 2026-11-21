import QtQuick
import Quickshell
import Quickshell.Io
import "RamStatus.js" as RamStatus

Scope {
  id: root
  property bool active: false
  property bool detailsVisible: false
  property string path: (Quickshell.env("DESKTOP_SHELL_PROC_ROOT") || "/proc") + "/meminfo"
  property int interval: 5000
  property var data: RamStatus.unavailable()
  property var topProcesses: null

  function refresh() {
    if (root.active) memoryFile.reload();
  }

  onActiveChanged: if (!active) root.data = RamStatus.unavailable()
  onDetailsVisibleChanged: {
    if (detailsVisible) {
      if (!processSampler.running) processSampler.running = true;
    } else {
      root.topProcesses = null;
    }
  }

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

  Timer {
    interval: root.interval
    running: root.detailsVisible
    repeat: true
    onTriggered: if (!processSampler.running) processSampler.running = true
  }

  Process {
    id: processSampler
    command: ["ps", "-e", "-ww", "-o", "pid=,rss=,comm=", "--sort=-rss,pid"]
    stdout: StdioCollector { id: processOutput }
    onExited: code => {
      if (root.detailsVisible)
        root.topProcesses = code === 0 ? RamStatus.topProcesses(processOutput.text) : [];
    }
  }
}
