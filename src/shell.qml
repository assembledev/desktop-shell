pragma ComponentBehavior: Bound
//@ pragma UseQApplication
//@ pragma DefaultEnv QS_NO_RELOAD_POPUP=1

import QtQuick
import Quickshell
import Quickshell.Io
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
import "modules/wallpaper_picker"
import "modules/window_switcher"

ShellRoot {
  id: root
  ShellConfig { id: shellConfig }
  ScreenPlacement { id: commandPlacement; configuration: shellConfig }

  function barFor(screen) {
    return bars.instances.find(bar => bar.screen === screen) || null;
  }

  IpcHandler {
    target: "desktopShell"
    function ping(): bool { return true; }
  }

  BarState {
    id: barState
    onPowerRequested: action => {
      commandPlacement.capture();
      for (const bar of bars.instances) {
        if (action === "close" || bar.screen !== commandPlacement.screen)
          bar.power("close");
        else
          bar.power(action);
      }
    }
  }
  Variants {
    id: bars
    model: shellConfig.barScreens
    Bar {
      required property var modelData
      screen: modelData
      sharedState: barState
      networkDetailsOpen: networkDetails.open && networkDetails.screen === screen
      onCalendarToggleRequested: calendar.toggleCalendar(screen)
      onControlCenterToggleRequested: controlCenter.toggleOpen(false, screen)
      onNetworkToggleRequested: networkDetails.toggleDetails(screen)
    }
  }
  CalendarPopup {
    id: calendar
    barSurface: root.barFor(screen)?.surface || null
  }
  CheatSheet {}
  ClipboardHistory {}
  ControlCenter {
    id: controlCenter
    barSurface: root.barFor(screen)?.surface || null
  }
  NetworkDetails {
    id: networkDetails
    model: barState.connection
    barSurface: root.barFor(screen)?.surface || null
    onWifiRequested: screen => controlCenter.openWifiPage(false, screen)
  }
  Connections {
    target: networkDetails
    function onOpenChanged() {
      if (networkDetails.open) {
        calendar.closeCalendar();
        controlCenter.open = false;
      }
    }
  }
  Connections {
    target: controlCenter
    function onOpenChanged() { if (controlCenter.open) networkDetails.closeDetails(); }
  }
  Connections {
    target: calendar
    function onOpenChanged() { if (calendar.open) networkDetails.closeDetails(); }
  }
  Connections {
    target: barState
    function onBarOpenChanged() { if (!barState.barOpen) networkDetails.closeDetails(); }
  }
  Launcher {}
  LockPreview {}
  NowPlaying {}
  WallpaperPicker {}
  WindowSwitcher {}
}
