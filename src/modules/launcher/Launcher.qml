import QtQuick
import Quickshell
import Quickshell.Io

Scope {
  id: root

  property var pendingCalls: []

  function enqueue(method, argument) {
    pendingCalls.push({ method: method, argument: argument });
    unloadTimer.stop();
    launcherLoader.active = true;
    flushTimer.restart();
  }

  function flushPending() {
    if (!launcherLoader.item)
      return;

    const calls = pendingCalls;
    pendingCalls = [];
    for (const call of calls) {
      if (call.argument === undefined)
        launcherLoader.item[call.method]();
      else
        launcherLoader.item[call.method](call.argument);
    }
  }

  function scheduleUnload() {
    // Keep the launcher view warm so DesktopEntries is populated before the
    // first visible open after boot or a shell restart.
  }

  function profileReady(profile) {
    return launcherLoader.item ? launcherLoader.item.profileReady(profile) : false;
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
    function profileReady(profile: string): bool { return root.profileReady(profile); }
    function applyProfile(profile: string): void { root.enqueue("applyProfile", profile); }
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
