pragma ComponentBehavior: Bound
//@ pragma UseQApplication
//@ pragma DefaultEnv QS_NO_RELOAD_POPUP=1

import Quickshell
import Quickshell.Io
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
  IpcHandler {
    target: "desktopShell"
    function ping(): bool { return true; }
  }

  Bar { id: bar }
  CalendarPopup { barSurface: bar.surface }
  CheatSheet {}
  ClipboardHistory {}
  ControlCenter { barSurface: bar.surface }
  Launcher {}
  LockPreview {}
  NowPlaying {}
  WallpaperPicker {}
  WindowSwitcher {}
}
