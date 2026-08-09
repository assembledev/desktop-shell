import QtQuick
import Quickshell
import Quickshell.Hyprland
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

  function hasAltTabSession() {
    if (pendingCalls.some(function(call) { return call.method === "altTab"; }))
      return true;

    const view = switcherLoader.item;
    return view && view.sessionActive;
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
      if (!root.hasAltTabSession() && root.pendingCalls.length === 0 && root.dropLateOpen())
        return;

      root.enqueue("altTab", action || "next");
    }
    function commit(): void {
      if (!root.hasAltTabSession() && root.pendingCalls.length === 0) {
        root.markCloseBeforeOpen();
        return;
      }

      root.enqueue("commit");
    }
    function cancel(): void {
      if (!root.hasAltTabSession() && root.pendingCalls.length === 0) {
        root.markCloseBeforeOpen();
        return;
      }

      root.enqueue("cancel");
    }
    function direction(code: string): void {
      root.routeDirection(code);
    }
  }

  Connections {
    target: Hyprland

    function onRawEvent(event) {
      if (event.name !== "custom")
        return;

      const prefix = "desktop-shell:window-switcher:";
      const payload = String(event.data || "");
      if (!payload.startsWith(prefix))
        return;

      const action = payload.slice(prefix.length);
      if (action === "next" || action === "prev")
        root.enqueue("altTab", action);
      else if (action === "commit" || action === "cancel")
        root.enqueue(action);
      else if (action.startsWith("direction:"))
        root.routeDirection(action.slice("direction:".length));
    }
  }

  Loader {
    id: switcherLoader
    // The controller is cheap while closed and must be ready before the first
    // Alt-Tab chord. Preview captures remain gated by WindowSwitcherView.open.
    active: true
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

}
