pragma ComponentBehavior: Bound
//@ pragma UseQApplication
//@ pragma DefaultEnv QS_NO_RELOAD_POPUP=1

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
      onCalendarToggleRequested: calendar.toggleCalendar(screen)
      onControlCenterToggleRequested: controlCenter.toggleOpen(false, screen)
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
  Launcher {}
  LockPreview {}
  NowPlaying {}
  WallpaperPicker {}
  WindowSwitcher {}
}
