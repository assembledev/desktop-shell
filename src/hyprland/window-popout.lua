local popoutTag = "desktop-popout"
local tiledTag = "desktop-popout-return-tiled"
local fitWarnings = {}

local function notify(message)
  hl.notification.create({ text = "Pop-out: " .. tostring(message), timeout = 3500 })
end

local function perform(action)
  local result = hl.dispatch(action)
  if not result or not result.ok then
    error(result and result.error or "Window action failed", 0)
  end
end

local function hasTag(window, tag)
  for _, value in ipairs(window.tags) do
    if value == tag then return true end
  end
  return false
end

local function setTag(window, tag, enabled)
  perform(hl.dsp.window.tag({ window = window, tag = (enabled and "+" or "-") .. tag }))
end

local function clearMarkers(window)
  if hasTag(window, popoutTag) then setTag(window, popoutTag, false) end
  if hasTag(window, tiledTag) then setTag(window, tiledTag, false) end
  fitWarnings[window.stable_id] = nil
end

local function mark(window, returnTiled)
  setTag(window, tiledTag, returnTiled)
  setTag(window, popoutTag, true)
end

local function workArea(monitor)
  if not monitor or monitor.scale <= 0 then return nil end
  local width, height = monitor.width / monitor.scale, monitor.height / monitor.scale
  if monitor.transform % 2 == 1 then width, height = height, width end
  local reserved = monitor.reserved
  local area = {
    x = monitor.x + reserved.left,
    y = monitor.y + reserved.top,
    width = width - reserved.left - reserved.right,
    height = height - reserved.top - reserved.bottom,
  }
  if area.width < 1 or area.height < 1 then return nil end
  return area
end

local function eligible(window)
  if window.fullscreen ~= 0 or window.fullscreen_client ~= 0 then
    return false, "Exit fullscreen or maximized mode first."
  end
  if window.group then return false, "Grouped windows are not supported." end
  if not window.workspace or window.workspace.special then
    return false, "Use a window on an ordinary workspace."
  end
  return true
end

local function resize(window, width, height)
  perform(hl.dsp.window.resize({ window = window, x = width, y = height }))
end

local function move(window, x, y)
  perform(hl.dsp.window.move({ window = window, x = x, y = y }))
end

local function setFloating(window, floating)
  perform(hl.dsp.window.float({ window = window, action = floating and "on" or "off" }))
end

local function setPinned(window, pinned)
  perform(hl.dsp.window.pin({ window = window, action = pinned and "on" or "off" }))
end

local function enter(window, options)
  local area = workArea(window.monitor)
  if not area then notify("No usable monitor area."); return end
  -- This snapshot exists only during the invocation, for failed-action rollback.
  local before = { floating = window.floating, at = window.at, size = window.size }
  local ok, failure = pcall(function()
    setFloating(window, true)
    local aspectRatio = options.aspectRatio or 1.6
    local height = math.min(
      area.width * (options.widthFraction or 0.70) / aspectRatio,
      area.height * (options.maxHeightFraction or 0.75)
    )
    resize(window, math.max(1, math.floor(height * aspectRatio + 0.5)), math.max(1, math.floor(height + 0.5)))
    local size = window.size
    if size.x > area.width or size.y > area.height then
      error("This window's minimum size does not fit the monitor.", 0)
    end
    move(window, math.floor(area.x + (area.width - size.x) / 2), math.floor(area.y + (area.height - size.y) / 2))
    setPinned(window, true)
    perform(hl.dsp.window.alter_zorder({ window = window, mode = "top" }))
    if not window.floating or not window.pinned then error("The window could not be pinned.", 0) end
    mark(window, not before.floating)
  end)
  if not ok then
    local restored = pcall(function()
      clearMarkers(window)
      if window.pinned then setPinned(window, false) end
      setFloating(window, before.floating)
      if before.floating then
        resize(window, before.size.x, before.size.y)
        move(window, before.at.x, before.at.y)
      end
    end)
    notify(tostring(failure) .. (restored and "" or " Could not fully restore the window."))
  end
end

local function leave(window, toggleFloating)
  local managed, returnTiled = hasTag(window, popoutTag), hasTag(window, tiledTag)
  local ok, failure = pcall(function()
    if window.pinned then setPinned(window, false) end
    clearMarkers(window)
    if toggleFloating then
      perform(hl.dsp.window.float({ window = window, action = "toggle" }))
    elseif managed and returnTiled then
      setFloating(window, false)
    end
  end)
  if not ok then
    local restored = pcall(function()
      setFloating(window, true)
      setPinned(window, true)
      if managed then mark(window, returnTiled) end
    end)
    notify(tostring(failure) .. (restored and "" or " Could not fully restore the pop-out."))
  end
end

local windowPopout = {
  toggle = function(options)
    local window = hl.get_active_window()
    if not window or not window.mapped then return end
    local allowed, reason = eligible(window)
    if not allowed then notify(reason); return end
    if hasTag(window, popoutTag) and (not window.floating or not window.pinned) then
      clearMarkers(window)
    end
    if window.pinned then leave(window, false) else enter(window, options or {}) end
  end,
  toggleFloating = function()
    local window = hl.get_active_window()
    if not window then return end
    if hasTag(window, popoutTag) then
      local allowed, reason = eligible(window)
      if not allowed then notify(reason); return end
      leave(window, true)
    else
      local ok, failure = pcall(function()
        perform(hl.dsp.window.float({ window = window, action = "toggle" }))
      end)
      if not ok then notify(failure) end
    end
  end,
}

local function keepReachable(window)
  if not window.mapped then return end
  if not window.floating or not window.pinned then clearMarkers(window); return end
  if not eligible(window) then return end
  local area = workArea(window.monitor)
  if not area then return end
  local size = window.size
  local factor = math.min(1, area.width / size.x, area.height / size.y)
  if factor < 1 then
    resize(window, math.max(1, math.floor(size.x * factor)), math.max(1, math.floor(size.y * factor)))
    size = window.size
  end
  local at = window.at
  local x = math.max(area.x, math.min(at.x, area.x + area.width - size.x))
  local y = math.max(area.y, math.min(at.y, area.y + area.height - size.y))
  if x ~= at.x or y ~= at.y then move(window, x, y) end
  if size.x > area.width or size.y > area.height then
    if not fitWarnings[window.stable_id] then
      notify("This window's minimum size exceeds the monitor; its top-left corner remains reachable.")
      fitWarnings[window.stable_id] = true
    end
  else
    fitWarnings[window.stable_id] = nil
  end
end

-- Coalesce topology events after Hyprland has migrated windows; never poll.
local reflowPending = false
local function scheduleReflow()
  if reflowPending or #hl.get_windows({ tag = popoutTag }) == 0 then return end
  reflowPending = true
  hl.timer(function()
    reflowPending = false
    for _, window in ipairs(hl.get_windows({ tag = popoutTag })) do
      local ok, failure = pcall(keepReachable, window)
      if not ok then notify(failure) end
    end
  end, { timeout = 50, type = "oneshot" })
end

hl.on("window.pin", function(window)
  if not window.pinned then clearMarkers(window) end
end)
hl.on("window.close", function(window) fitWarnings[window.stable_id] = nil end)
hl.on("window.move_to_workspace", function(window)
  if hasTag(window, popoutTag) then scheduleReflow() end
end)
hl.on("monitor.layout_changed", scheduleReflow)
hl.on("monitor.removed", scheduleReflow)
hl.on("config.reloaded", scheduleReflow)

return windowPopout
