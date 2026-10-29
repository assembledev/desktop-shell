import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "../common"

Scope {
  id: root

  ShellConfig { id: shellConfig }
  ScreenPlacement { id: commandPlacement; configuration: shellConfig }

  property var pendingCalls: []

  function enqueue(method, argument) {
    pendingCalls.push({ method: method, argument: argument, screen: commandPlacement.capture() });
    flushTimer.restart();
  }

  function flushPending() {
    if (!launcherLoader.item)
      return;

    const calls = pendingCalls;
    pendingCalls = [];
    for (const call of calls) {
      if (call.argument === undefined)
        launcherLoader.item[call.method](call.screen);
      else
        launcherLoader.item[call.method](call.argument);
    }
  }

  function profileReady(profile) {
    return launcherLoader.item ? launcherLoader.item.profileReady(profile) : false;
  }

  IpcHandler {
    target: "launcher"
    function open(): void { root.enqueue("openLauncher"); }
    function focus(): void { root.enqueue("openFocusLauncher"); }
    function close(): void { root.enqueue("closeLauncher"); }
    function toggle(): void { root.enqueue("toggleLauncher"); }
    function profileReady(profile: string): bool { return root.profileReady(profile); }
    function applyProfile(profile: string): void { root.enqueue("applyProfile", profile); }
    function profileStatus(profile: string, refresh: bool): string {
      if (!launcherLoader.item)
        return JSON.stringify({ error: { code: "not-ready", message: "Launcher model is not ready" } });
      return JSON.stringify(launcherLoader.item.profileStatus(profile, refresh));
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "custom" && event.data === "desktop-shell:launcher:toggle")
        root.enqueue("toggleLauncher");
    }
  }

  Loader {
    id: launcherLoader
    // Keep DesktopEntries warm before the first visible open.
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

}
