pragma ComponentBehavior: Bound
//@ pragma UseQApplication
//@ pragma DefaultEnv QS_NO_RELOAD_POPUP=1

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "modules/common"
import "modules/bar"
import "modules/calendar"
import "modules/cheatsheet"
import "modules/clipboard_history"
import "modules/control_center"
import "modules/launcher"
import "modules/lock"
import "modules/now_playing"
import "modules/network"
import "modules/tailscale"
import "modules/wallpaper_picker"
import "modules/window_switcher"

ShellRoot {
  id: root
  ShellConfig { id: shellConfig }
  ScreenPlacement { id: commandPlacement; configuration: shellConfig }

  function barFor(screen) {
    return bars.instances.find(bar => bar.screen === screen) || null;
  }

  property var activeTasks: ({})

  function activeTaskFor(screen) {
    return activeTasks[String(screen?.name || "")] || null;
  }

  function requestTask(task, screen) {
    const output = String(screen?.name || "");
    if (output.length === 0)
      return;
    const previous = activeTasks[output];
    if (previous === task)
      return;
    const next = Object.assign({}, activeTasks);
    for (const name of Object.keys(next)) {
      if (next[name] === task)
        delete next[name];
    }
    next[output] = task;
    activeTasks = next;
    if (previous && previous !== task)
      previous.cancelTask();
  }

  function releaseTask(task) {
    const next = Object.assign({}, activeTasks);
    let changed = false;
    for (const output of Object.keys(next)) {
      if (next[output] === task) {
        delete next[output];
        changed = true;
      }
    }
    if (changed)
      activeTasks = next;
  }

  IpcHandler {
    target: "desktopShell"
    function ping(): bool { return true; }
  }

  BarState {
    id: barState
    onPowerRequested: action => {
      const screen = commandPlacement.capture();
      root.barFor(screen)?.power(action);
    }
  }
  Variants {
    id: bars
    model: shellConfig.barScreens
    Bar {
      id: bar
      required property var modelData
      screen: modelData
      sharedState: barState
      taskHost: root
      tailscaleDetailsOpen: tailscaleDetails.open && tailscaleDetails.screen === screen
      onTailscaleToggleRequested: tailscaleDetails.toggleDetails(screen)
      profileDetailsId: networkProfiles.open && networkProfiles.screen === screen ? networkProfiles.controlId : ""
      onProfilesToggleRequested: (controlId, trigger) => networkProfiles.toggleDetails(controlId, screen, trigger)
      networkDetailsOpen: networkDetails.open && networkDetails.screen === screen
      onCalendarToggleRequested: calendar.toggleCalendar(screen)
      onControlCenterToggleRequested: controlCenter.toggleOpen(false, screen)
      onNetworkToggleRequested: networkDetails.toggleDetails(screen)
    }
  }
  CalendarPopup {
    taskHost: root
    id: calendar
    barSurface: root.barFor(screen)?.surface || null
  }
  CheatSheet { taskHost: root }
  ClipboardHistory { taskHost: root }
  ControlCenter {
    taskHost: root
    id: controlCenter
    barSurface: root.barFor(screen)?.surface || null
  }
  BatteryNotifications {
    data: barState.batteryState.data
    onDismissRequested: id => controlCenter.dismissNotification(id)
  }
  NetworkDetails {
    taskHost: root
    id: networkDetails
    model: barState.connection
    barSurface: root.barFor(screen)?.surface || null
    onWifiRequested: screen => controlCenter.openWifiPage(false, screen)
  }
  TailscaleDetails {
    taskHost: root
    id: tailscaleDetails
    model: barState.tailscale
    networkController: barState.network
    barSurface: root.barFor(screen)?.surface || null
  }
  TaildropNotifications {
    id: taildropNotifications
    onSaveRequested: files => tailscaleDetails.saveReceived(files)
  }
  NetworkProfiles {
    taskHost: root
    id: networkProfiles
    controller: barState.network
    barSurface: root.barFor(screen)?.surface || null
  }
  Connections {
    target: barState.tailscale
    function onFilesReceived(files) {
      const icon = barState.network.controls.find(control => control.id === "tailscale")?.icon || "";
      taildropNotifications.notify(files, icon);
    }
  }
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      const prefix = "desktop-shell:dismiss-shell-popup:";
      if (event.name === "custom" && String(event.data || "").startsWith(prefix)) {
        const output = String(event.data).slice(prefix.length);
        root.activeTasks[output]?.cancelTask();
      }
    }
  }
  Connections {
    target: barState
    function onBarOpenChanged() { if (!barState.barOpen) { networkDetails.closeDetails(); tailscaleDetails.closeDetails(); networkProfiles.closeDetails(); } }
  }
  Launcher { taskHost: root }
  LockPreview {}
  NowPlaying {}
  WallpaperPicker { taskHost: root }
  WindowSwitcher { taskHost: root }
}
