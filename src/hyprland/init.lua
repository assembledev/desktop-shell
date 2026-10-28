-- Load this file from the Hyprland Lua configuration and keep its returned API.
local directory = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local desktopShell = {
  windowPopout = dofile(directory .. "window-popout.lua"),
}

dofile(directory .. "popup-escape.lua")

-- Shell-owned surfaces share the same glass treatment in every installation.
local blurLayers = {
  "quickshell:bar",
  "quickshell:batteryAnalysis",
  "quickshell:calendar",
  "quickshell:trayMenu",
  "quickshell:trayShelf",
  "quickshell:powerMenu",
  "quickshell:launcher",
  "quickshell:controlCenter",
  "quickshell:network",
  "quickshell:tailscale",
  "quickshell:controlCenterOsd",
  "quickshell:notificationPopups",
  "quickshell:nowPlaying",
  "quickshell:clipboardHistory",
  "quickshell:cheatsheet",
  "quickshell:windowSwitcher",
}

for _, namespace in ipairs(blurLayers) do
  hl.layer_rule({
    match = { namespace = namespace },
    blur = true,
    ignore_alpha = 0.5,
  })
end

return desktopShell
