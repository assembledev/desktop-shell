# Fixed variable names only; values are transported as data, never shell code.
def config_string: if type == "string" then . else "" end;

if type != "object" then error("configuration must be an object") else . end |
{
  DESKTOP_SHELL_WORKSPACES_JSON: (.workspaces.items // [] | tojson),
  DESKTOP_SHELL_SCROLLING_WORKSPACE: (.workspaces.scrolling | config_string),
  DESKTOP_SHELL_OUTPUT: (.output | config_string),
  DESKTOP_SHELL_BAR_COMPACT: (if .bar.compact // false then "1" else "0" end),
  DESKTOP_SHELL_BAR_SHOW_VRAM: (if .bar.showVram // true then "1" else "0" end),
  DESKTOP_SHELL_BAR_WORKSPACE_ICONS: (if .bar.workspaceIcons // true then "1" else "0" end),
  DESKTOP_SHELL_KEYBOARD_LABELS_JSON: (.keyboard.layoutLabels // ["EN"] | tojson),
  DESKTOP_SHELL_BROWSER_TABS: (if .browserTabs.enable // false then "1" else "0" end),
  DESKTOP_SHELL_BROWSER_ENTRY_ID: (.browserTabs.desktopEntryId | config_string),
  DESKTOP_SHELL_BROWSER_NAME: (.browserTabs.displayName | config_string),
  DESKTOP_SHELL_BROWSER_ICON: (.browserTabs.icon | config_string),
  DESKTOP_SHELL_LAUNCH_PROFILES_JSON: (.launcher.profiles // {} | tojson),
  DESKTOP_SHELL_THEME_JSON: (.theme // {} | tojson),
  DESKTOP_SHELL_LOCK_KEYBOARD_INDEX: (.lock.keyboardLayoutIndex | config_string),
  DESKTOP_SHELL_LOGIN_WALLPAPER_SYNC: (.integrations.loginWallpaperSync | config_string),
  DESKTOP_SHELL_PRIVILEGED_HELPER: (.integrations.privilegedHelper | config_string),
  recording_state_file: (.integrations.recordingStateFile | config_string),
  wallpaper_dir: (.wallpaper.directory | config_string),
  default_wallpaper: (.wallpaper.default | config_string)
} |
to_entries |
map(if .value | contains("\u0000") then error("NUL in configuration value") else . end) |
.[] | .key, "\u0000", .value, "\u0000"
