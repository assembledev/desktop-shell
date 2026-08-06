import QtQuick
import Quickshell
import Quickshell.Io
import "../common"

Scope {
  id: root

  HyprlandAdapter { id: hyprland }

  property var pendingCalls: []
  property double closeBeforeOpenUntil: 0

  function markCloseBeforeOpen() {
    closeBeforeOpenUntil = Date.now() + 500;
  }

  function dropLateOpen() {
    if (Date.now() > closeBeforeOpenUntil)
      return false;

    closeBeforeOpenUntil = 0;
    return true;
  }

  function enqueue(method, argument) {
    pendingCalls.push({ method: method, argument: argument });
    unloadTimer.stop();
    switcherLoader.active = true;
    flushTimer.restart();
  }

  function flushPending() {
    if (!switcherLoader.item)
      return;

    const calls = pendingCalls;
    pendingCalls = [];
    for (const call of calls) {
      if (call.argument === undefined)
        switcherLoader.item[call.method]();
      else
        switcherLoader.item[call.method](call.argument);
    }
  }

  function scheduleUnload() {
    if (pendingCalls.length === 0)
      unloadTimer.restart();
  }

  function hasAltTabSession() {
    if (pendingCalls.some(function(call) { return call.method === "altTab"; }))
      return true;

    const view = switcherLoader.item;
    return view && (view.open || view.refreshForOpen);
  }

  function routeDirection(code) {
    const directions = {
      l: "left",
      r: "right",
      u: "up",
      d: "down"
    };
    const direction = directions[code];
    if (!direction)
      return;

    if (hasAltTabSession()) {
      enqueue("selectDirection", direction);
      return;
    }

    hyprland.focusDirection(code);
  }

  IpcHandler {
    target: "windowSwitcher"
    function alttab(action: string): void {
      if (!switcherLoader.active && root.pendingCalls.length === 0 && root.dropLateOpen())
        return;

      root.enqueue("altTab", action || "next");
    }
    function commit(): void {
      if (!switcherLoader.active && root.pendingCalls.length === 0) {
        root.markCloseBeforeOpen();
        return;
      }

      root.enqueue("commit");
      root.scheduleUnload();
    }
    function cancel(): void {
      if (!switcherLoader.active && root.pendingCalls.length === 0) {
        root.markCloseBeforeOpen();
        return;
      }

      root.enqueue("cancel");
      root.scheduleUnload();
    }
    function direction(code: string): void {
      root.routeDirection(code);
    }
  }

  Loader {
    id: switcherLoader
    active: false
    asynchronous: false
    sourceComponent: WindowSwitcherView {}
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
      if (!switcherLoader.item)
        return;
      if (switcherLoader.item.canUnload())
        switcherLoader.active = false;
      else
        restart();
    }
  }

  Connections {
    target: switcherLoader.item
    ignoreUnknownSignals: true
    function onOpenChanged() {
      if (!switcherLoader.item.open)
        root.scheduleUnload();
    }
  }
}
