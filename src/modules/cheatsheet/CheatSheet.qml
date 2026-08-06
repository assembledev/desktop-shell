import QtQuick
import Quickshell
import Quickshell.Io

Scope {
  id: root

  property var pendingCalls: []

  function enqueue(method) {
    pendingCalls.push(method);
    unloadTimer.stop();
    cheatsheetLoader.active = true;
    flushTimer.restart();
  }

  function flushPending() {
    if (!cheatsheetLoader.item)
      return;

    const calls = pendingCalls;
    pendingCalls = [];
    for (const method of calls)
      cheatsheetLoader.item[method]();
  }

  function scheduleUnload() {
    if (pendingCalls.length === 0)
      unloadTimer.restart();
  }

  IpcHandler {
    target: "cheatsheet"
    function open(): void { root.enqueue("openSheet"); }
    function close(): void {
      if (!cheatsheetLoader.active && root.pendingCalls.length === 0)
        return;
      root.enqueue("closeSheet");
      root.scheduleUnload();
    }
    function toggle(): void { root.enqueue("toggleSheet"); }
  }

  Loader {
    id: cheatsheetLoader
    active: false
    asynchronous: false
    sourceComponent: CheatSheetView {}
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
      if (!cheatsheetLoader.item)
        return;
      if (!cheatsheetLoader.item.open)
        cheatsheetLoader.active = false;
      else
        restart();
    }
  }

  Connections {
    target: cheatsheetLoader.item
    ignoreUnknownSignals: true
    function onOpenChanged() {
      if (!cheatsheetLoader.item.open)
        root.scheduleUnload();
    }
  }
}
