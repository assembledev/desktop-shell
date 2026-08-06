import QtQuick
import Quickshell
import Quickshell.Io

Scope {
  id: root

  property var pendingCalls: []

  function enqueue(method) {
    pendingCalls.push(method);
    unloadTimer.stop();
    launcherLoader.active = true;
    flushTimer.restart();
  }

  function flushPending() {
    if (!launcherLoader.item)
      return;

    const calls = pendingCalls;
    pendingCalls = [];
    for (const method of calls)
      launcherLoader.item[method]();
  }

  function scheduleUnload() {
    // Keep the launcher view warm so DesktopEntries is populated before the
    // first visible open after boot or a shell restart.
  }

  IpcHandler {
    target: "launcher"
    function open(): void { root.enqueue("openLauncher"); }
    function focus(): void { root.enqueue("openFocusLauncher"); }
    function close(): void {
      if (!launcherLoader.active && root.pendingCalls.length === 0)
        return;
      root.enqueue("closeLauncher");
      root.scheduleUnload();
    }
    function toggle(): void { root.enqueue("toggleLauncher"); }
  }

  Loader {
    id: launcherLoader
    active: true
    asynchronous: false
    sourceComponent: LauncherView {}
    onLoaded: flushTimer.restart()
  }

  Timer {
    id: flushTimer
    interval: 0
    repeat: false
    onTriggered: root.flushPending()
  }

  Timer {
    id: unloadTimer
    interval: 1200
    repeat: false
    onTriggered: {
      if (!launcherLoader.item)
        return;
      if (!launcherLoader.item.open)
        launcherLoader.active = false;
      else
        restart();
    }
  }

  Connections {
    target: launcherLoader.item
    ignoreUnknownSignals: true
    function onOpenChanged() {
      if (!launcherLoader.item.open)
        root.scheduleUnload();
    }
  }
}
