local toastDismissEvents = {
  ["quickshell:notificationPopups"] = "desktop-shell:dismiss-notification-popups",
  ["quickshell:nowPlaying"] = "desktop-shell:dismiss-now-playing",
}
local shellPopupDismissEvent = "desktop-shell:dismiss-shell-popup"
local shellPopupNamespaces = {
  ["quickshell:calendar"] = true,
  ["quickshell:network"] = true,
  ["quickshell:tailscale"] = true,
  ["quickshell:controlCenter"] = true,
  ["quickshell:powerMenu"] = true,
}
local popupEscapeBind

local function popupMapped(namespace, excludedLayer)
  for _, layer in ipairs(hl.get_layers({ namespace = namespace })) do
    if layer ~= excludedLayer and layer.mapped then
      return true
    end
  end
  return false
end

local function anyPopupMapped(namespaces, excludedLayer)
  for namespace, _ in pairs(namespaces) do
    if popupMapped(namespace, excludedLayer) then
      return true
    end
  end

  return false
end

local function dismissPopup()
  if anyPopupMapped(shellPopupNamespaces) then
    hl.dispatch(hl.dsp.event(shellPopupDismissEvent))
  else
    for namespace, event in pairs(toastDismissEvents) do
      if popupMapped(namespace) then
        hl.dispatch(hl.dsp.event(event))
      end
    end
  end
end

local function syncPopupEscapeBind(excludedLayer)
  popupEscapeBind:set_enabled(
    anyPopupMapped(shellPopupNamespaces, excludedLayer) or anyPopupMapped(toastDismissEvents, excludedLayer)
  )
end

popupEscapeBind = hl.bind(
  "Escape",
  dismissPopup,
  {
    description = "Dismiss the active desktop-shell popup",
    dont_inhibit = true,
    submap_universal = true,
  }
)

hl.on("layer.opened", function(layer)
  if toastDismissEvents[layer.namespace] or shellPopupNamespaces[layer.namespace] then
    popupEscapeBind:set_enabled(true)
  end
end)

hl.on("layer.closed", function(layer)
  if toastDismissEvents[layer.namespace] or shellPopupNamespaces[layer.namespace] then
    -- Hyprland emits layer.closed before marking the closing layer unmapped.
    syncPopupEscapeBind(layer)
  end
end)

syncPopupEscapeBind()
