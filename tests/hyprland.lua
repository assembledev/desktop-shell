local sourceRoot = assert(arg[1], "source root is required")
local loader = arg[2] or sourceRoot .. "/src/hyprland/init.lua"
local tests = 0

local function equal(actual, expected, message)
  assert(actual == expected, (message or "unexpected value") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end

local function tagged(window, tag)
  for _, value in ipairs(window.tags) do
    if value == tag then return true end
  end
  return false
end

local function setup(initialLayers)
  local state = { actions = {}, events = {}, handlers = {}, timers = {}, bindings = {}, layers = initialLayers or {}, rules = {}, notifications = {}, windows = {} }
  local function action(kind, options)
    return { kind = kind, options = options }
  end
  hl = {
    dsp = { window = {} },
    notification = { create = function(options) table.insert(state.notifications, options.text) end },
    get_active_window = function() return state.active end,
    get_windows = function(options)
      local windows = {}
      for _, window in ipairs(state.windows) do
        if tagged(window, options.tag) then table.insert(windows, window) end
      end
      return windows
    end,
    get_layers = function(options)
      local layers = {}
      for _, layer in ipairs(state.layers) do
        if layer.namespace == options.namespace then table.insert(layers, layer) end
      end
      return layers
    end,
    on = function(event, callback)
      state.handlers[event] = state.handlers[event] or {}
      table.insert(state.handlers[event], callback)
    end,
    timer = function(callback, options)
      equal(options.timeout, 50)
      equal(options.type, "oneshot")
      table.insert(state.timers, callback)
    end,
    bind = function(key, callback, options)
      local binding = { key = key, callback = callback, options = options }
      function binding:set_enabled(enabled) self.enabled = enabled end
      table.insert(state.bindings, binding)
      return binding
    end,
    layer_rule = function(options) table.insert(state.rules, options) end,
  }
  function state.emit(event, value)
    for _, callback in ipairs(state.handlers[event] or {}) do callback(value) end
  end
  function state.flush()
    local timers = state.timers
    state.timers = {}
    for _, callback in ipairs(timers) do callback() end
  end
  for _, kind in ipairs({ "tag", "resize", "move", "float", "pin", "alter_zorder" }) do
    hl.dsp.window[kind] = function(options) return action(kind, options) end
  end
  hl.dsp.event = function(name) return action("event", name) end
  hl.dispatch = function(request)
    table.insert(state.actions, request)
    if state.fail == request.kind then
      state.fail = nil
      return { ok = false, error = "injected " .. request.kind .. " failure" }
    end
    local options = request.options
    if request.kind == "event" then
      table.insert(state.events, options)
    else
      local window = options.window
      if request.kind == "float" then
        window.floating = options.action == "on" or (options.action == "toggle" and not window.floating)
      elseif request.kind == "pin" then
        window.pinned = options.action == "on"
        state.emit("window.pin", window)
      elseif request.kind == "resize" then
        window.size = { x = math.max(options.x, window.minimumWidth or 1), y = math.max(options.y, window.minimumHeight or 1) }
      elseif request.kind == "move" then
        window.at = { x = options.x, y = options.y }
      elseif request.kind == "tag" then
        local tag = options.tag:sub(2)
        for index = #window.tags, 1, -1 do
          if window.tags[index] == tag then table.remove(window.tags, index) end
        end
        if options.tag:sub(1, 1) == "+" then table.insert(window.tags, tag) end
      end
    end
    return { ok = true }
  end
  state.api = dofile(loader)
  state.escape = assert(state.bindings[1])
  function state.window(options)
    local window = {
      stable_id = tostring(#state.windows + 1), mapped = true,
      floating = false, pinned = false, tags = {}, fullscreen = 0, fullscreen_client = 0,
      workspace = { special = false }, at = { x = 100, y = 80 }, size = { x = 800, y = 500 },
      monitor = { x = 0, y = 0, width = 1600, height = 1000, scale = 1, transform = 0,
        reserved = { left = 0, right = 0, top = 0, bottom = 0 } },
    }
    for key, value in pairs(options or {}) do window[key] = value end
    table.insert(state.windows, window)
    state.active = window
    return window
  end
  function state.layer(namespace)
    local layer = { namespace = namespace, mapped = true }
    table.insert(state.layers, layer)
    state.emit("layer.opened", layer)
    return layer
  end
  return state
end

local function test(name, callback)
  local ok, failure = pcall(callback)
  assert(ok, name .. ": " .. tostring(failure))
  tests = tests + 1
end

test("loader exposes API and registers shell rules and handlers", function()
  desktopWindowPopout = nil
  local s = setup()
  equal(type(s.api.windowPopout.toggle), "function")
  equal(type(s.api.windowPopout.toggleFloating), "function")
  equal(desktopWindowPopout, nil, "legacy global must remain absent")
  equal(#s.bindings, 1)
  equal(s.escape.key, "Escape")
  equal(s.escape.enabled, false)
  equal(s.escape.options.dont_inhibit, true)
  equal(s.escape.options.submap_universal, true)
  local expected = {
    "bar", "batteryAnalysis", "calendar", "trayMenu", "trayShelf", "powerMenu", "launcher", "controlCenter",
    "network", "tailscale", "controlCenterOsd", "notificationPopups", "nowPlaying", "clipboardHistory", "cheatsheet", "windowSwitcher",
  }
  equal(#s.rules, #expected)
  for index, namespace in ipairs(expected) do
    equal(s.rules[index].match.namespace, "quickshell:" .. namespace)
    equal(s.rules[index].blur, true)
    equal(s.rules[index].ignore_alpha, 0.5)
  end
  for _, event in ipairs({ "window.pin", "window.close", "window.move_to_workspace", "monitor.layout_changed", "monitor.removed", "config.reloaded", "layer.opened", "layer.closed" }) do
    equal(#s.handlers[event], 1, event .. " registration")
  end
end)

test("tiled pop-out returns to tiling with original geometry policy", function()
  local s = setup()
  local w = s.window()
  s.api.windowPopout.toggle()
  equal(w.floating, true)
  equal(w.pinned, true)
  equal(w.size.x, 1120)
  equal(w.size.y, 700)
  equal(w.at.x, 240)
  equal(w.at.y, 150)
  equal(tagged(w, "desktop-popout"), true)
  equal(tagged(w, "desktop-popout-return-tiled"), true)
  s.api.windowPopout.toggle()
  equal(w.floating, false)
  equal(w.pinned, false)
  equal(#w.tags, 0)
end)

test("floating windows remain floating and geometry is caller-owned", function()
  local s = setup()
  local w = s.window({ floating = true })
  s.api.windowPopout.toggle({ widthFraction = 0.5, maxHeightFraction = 0.4, aspectRatio = 2 })
  equal(w.size.x, 800)
  equal(w.size.y, 400)
  equal(tagged(w, "desktop-popout-return-tiled"), false)
  s.api.windowPopout.toggle()
  equal(w.floating, true)
  equal(w.pinned, false)
end)

test("work area respects scale, rotation and reserved edges", function()
  local s = setup()
  local w = s.window()
  w.monitor = { x = 100, y = 200, width = 2000, height = 3200, scale = 2, transform = 1,
    reserved = { left = 20, right = 30, top = 40, bottom = 60 } }
  s.api.windowPopout.toggle()
  equal(w.size.x, 1080)
  equal(w.size.y, 675)
  equal(w.at.x, 355)
  equal(w.at.y, 352)
end)

test("failed entry restores floating geometry and clears tags", function()
  local s = setup()
  local w = s.window({ floating = true })
  s.fail = "pin"
  s.api.windowPopout.toggle()
  equal(w.floating, true)
  equal(w.pinned, false)
  equal(w.size.x, 800)
  equal(w.size.y, 500)
  equal(w.at.x, 100)
  equal(w.at.y, 80)
  equal(#w.tags, 0)
  assert(s.notifications[1]:find("injected pin failure", 1, true))
end)

test("windows that cannot fit fail safely", function()
  local s = setup()
  local w = s.window({ minimumWidth = 1800 })
  s.api.windowPopout.toggle()
  equal(w.floating, false)
  equal(w.pinned, false)
  equal(#w.tags, 0)
  assert(s.notifications[1]:find("minimum size does not fit", 1, true))
end)

test("failed exit restores a managed pop-out", function()
  local s = setup()
  local w = s.window()
  s.api.windowPopout.toggle()
  s.fail = "float"
  s.api.windowPopout.toggle()
  equal(w.floating, true)
  equal(w.pinned, true)
  equal(tagged(w, "desktop-popout"), true)
  equal(tagged(w, "desktop-popout-return-tiled"), true)
end)

test("ordinary and managed floating toggles preserve marker ownership", function()
  local s = setup()
  local w = s.window()
  s.api.windowPopout.toggleFloating()
  equal(w.floating, true)
  s.api.windowPopout.toggle()
  s.api.windowPopout.toggleFloating()
  equal(w.floating, false)
  equal(w.pinned, false)
  equal(#w.tags, 0)
end)

test("ineligible windows and absent focus cannot become pop-outs", function()
  for _, options in ipairs({ { fullscreen = 1 }, { fullscreen_client = 1 }, { group = {} }, { workspace = { special = true } }, { mapped = false } }) do
    local s = setup()
    local w = s.window(options)
    s.api.windowPopout.toggle()
    equal(#s.actions, 0)
    equal(w.pinned, false)
  end
  local s = setup()
  s.api.windowPopout.toggle()
  s.api.windowPopout.toggleFloating()
  equal(#s.actions, 0)
end)

test("topology events coalesce and keep marked windows reachable", function()
  local s = setup()
  local w = s.window()
  s.api.windowPopout.toggle()
  w.monitor.width, w.monitor.height, w.monitor.x, w.monitor.y = 1000, 600, 200, 100
  s.emit("monitor.layout_changed")
  s.emit("monitor.removed")
  s.emit("config.reloaded")
  s.emit("window.move_to_workspace", w)
  equal(#s.timers, 1)
  s.flush()
  equal(w.size.x, 960)
  equal(w.size.y, 600)
  equal(w.at.x, 240)
  equal(w.at.y, 100)
  w.pinned = false
  s.emit("window.pin", w)
  equal(#w.tags, 0)
  s.emit("monitor.layout_changed")
  equal(#s.timers, 0)
end)

test("oversized topology warning is deduplicated and cleared on close", function()
  local s = setup()
  local w = s.window()
  s.api.windowPopout.toggle()
  w.minimumWidth, w.minimumHeight = 1500, 900
  w.monitor.width, w.monitor.height = 700, 500
  s.emit("monitor.layout_changed")
  s.flush()
  equal(#s.notifications, 1)
  equal(w.at.x, 0)
  equal(w.at.y, 0)
  s.emit("config.reloaded")
  s.flush()
  equal(#s.notifications, 1)
  s.emit("window.close", w)
  s.emit("monitor.layout_changed")
  s.flush()
  equal(#s.notifications, 2)
end)

test("Escape detects existing mapped popups when the config loads", function()
  local s = setup({ { namespace = "quickshell:notificationPopups", mapped = true } })
  equal(s.escape.enabled, true)
  s.escape.callback()
  equal(s.events[1], "desktop-shell:dismiss-notification-popups")
end)

test("Escape follows mapped shell surfaces and prioritizes shell popups", function()
  local s = setup()
  local notification = s.layer("quickshell:notificationPopups")
  equal(s.escape.enabled, true)
  s.escape.callback()
  equal(s.events[1], "desktop-shell:dismiss-notification-popups")
  local popup = s.layer("quickshell:controlCenter")
  s.escape.callback()
  equal(s.events[2], "desktop-shell:dismiss-shell-popup")
  -- layer.closed arrives while the closing layer is still reported mapped.
  s.emit("layer.closed", popup)
  equal(s.escape.enabled, true)
  popup.mapped = false
  s.emit("layer.closed", notification)
  equal(s.escape.enabled, false)
  notification.mapped = false
  s.escape.callback()
  equal(#s.events, 2)
  s.layer("some-other-layer")
  equal(s.escape.enabled, false)
  local power = s.layer("quickshell:powerMenu")
  equal(s.escape.enabled, true)
  s.emit("layer.closed", power)
  equal(s.escape.enabled, false)
end)

print("Hyprland Lua: " .. tests .. " tests passed")
