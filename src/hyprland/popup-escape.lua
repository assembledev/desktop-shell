local shellTaskNamespaces = {
  ["quickshell:launcher"] = true,
  ["quickshell:clipboardHistory"] = true,
  ["quickshell:wallpaperPicker"] = true,
  ["quickshell:windowSwitcher"] = true,
  ["quickshell:cheatsheet"] = true,
  ["quickshell:calendar"] = true,
  ["quickshell:network"] = true,
  ["quickshell:network-profiles"] = true,
  ["quickshell:tailscale"] = true,
  ["quickshell:controlCenter"] = true,
  ["quickshell:powerMenu"] = true,
  ["quickshell:trayMenu"] = true,
}
local passiveDismissEvents = {
  ["quickshell:notificationPopups"] = "desktop-shell:dismiss-notification-popups:",
  ["quickshell:nowPlaying"] = "desktop-shell:dismiss-now-playing:",
}

local function dismissPopup()
  local monitor = hl.get_active_monitor()
  if not monitor then return { pass_event = true } end

  local taskMapped = false
  local passiveMapped = {}
  for _, layer in ipairs(hl.get_layers({ monitor = monitor })) do
    if layer.mapped then
      if shellTaskNamespaces[layer.namespace] then
        -- Lua exposes interactivity, not the keyboard-focused layer. Let an
        -- interactive task handle Escape locally (including tray Back).
        if layer.interactivity ~= 0 then return { pass_event = true } end
        taskMapped = true
      elseif passiveDismissEvents[layer.namespace] then
        passiveMapped[layer.namespace] = true
      end
    end
  end

  if taskMapped then
    hl.dispatch(hl.dsp.event("desktop-shell:dismiss-shell-popup:" .. monitor.name))
    return
  end

  local dismissed = false
  for namespace in pairs(passiveMapped) do
    hl.dispatch(hl.dsp.event(passiveDismissEvents[namespace] .. monitor.name))
    dismissed = true
  end
  if not dismissed then return { pass_event = true } end
end

hl.bind(
  "Escape",
  dismissPopup,
  {
    description = "Dismiss desktop-shell popups on the focused output",
    dont_inhibit = true,
    submap_universal = true,
  }
)
