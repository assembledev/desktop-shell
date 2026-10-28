local notificationPopupNamespace = "quickshell:notificationPopups"
local notificationPopupDismissEvent = "desktop-shell:dismiss-notification-popups"
local shellPopupDismissEvent = "desktop-shell:dismiss-shell-popup"
local shellPopupNamespaces = {
  ["quickshell:controlCenter"] = true,
  ["quickshell:powerMenu"] = true,
}
local popupEscapeBind

local function notificationPopupsMapped(excludedLayer)
  for _, layer in ipairs(hl.get_layers({ namespace = notificationPopupNamespace })) do
    if layer ~= excludedLayer and layer.mapped then
      return true
    end
  end
  return false
end

local function shellPopupMapped(excludedLayer)
  for namespace, _ in pairs(shellPopupNamespaces) do
    for _, layer in ipairs(hl.get_layers({ namespace = namespace })) do
      if layer ~= excludedLayer and layer.mapped then
        return true
      end
    end
  end

  return false
end

local function dismissPopup()
  if shellPopupMapped() then
    hl.dispatch(hl.dsp.event(shellPopupDismissEvent))
  elseif notificationPopupsMapped() then
    hl.dispatch(hl.dsp.event(notificationPopupDismissEvent))
  end
end

local function syncPopupEscapeBind(excludedLayer)
  popupEscapeBind:set_enabled(
    shellPopupMapped(excludedLayer) or notificationPopupsMapped(excludedLayer)
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
  if layer.namespace == notificationPopupNamespace or shellPopupNamespaces[layer.namespace] then
    popupEscapeBind:set_enabled(true)
  end
end)

hl.on("layer.closed", function(layer)
  if layer.namespace == notificationPopupNamespace or shellPopupNamespaces[layer.namespace] then
    -- Hyprland emits layer.closed before marking the closing layer unmapped.
    syncPopupEscapeBind(layer)
  end
end)

syncPopupEscapeBind()
