# Keybindings

Desktop Shell does not replace the keybinding policy in an existing Hyprland
configuration. Bind the commands you use, then provide matching keybinding
metadata to the Home Manager module if you want it shown in the built-in cheat
sheet.

## Suggested bindings

| Key | Command | Action |
| --- | --- | --- |
| `Alt+Space` | `desktop-shell launcher toggle` | Open the launcher |
| `Super+N` | `desktop-shell toggle` | Toggle the control center |
| `Super+V` | `desktop-shell clipboard open` | Open clipboard history |
| `Super+W` | `desktop-shell pick` | Open the wallpaper picker |
| `Super+/` | `desktop-shell cheatsheet toggle` | Open the keybinding reference |
| `Super+L` | `desktop-shell lock` | Lock the session |
| `Alt+Tab` | `desktop-shell alttab next` | Select the next window |
| `Alt+Shift+Tab` | `desktop-shell alttab prev` | Select the previous window |
| `Alt+Arrow` | `desktop-shell direction l|r|u|d` | Focus spatially |
| `XF86AudioRaiseVolume` | `desktop-shell volume up` | Raise output volume |
| `XF86AudioLowerVolume` | `desktop-shell volume down` | Lower output volume |
| `XF86AudioMute` | `desktop-shell volume mute` | Toggle output mute |
| `XF86MonBrightnessUp` | `desktop-shell brightness up` | Raise brightness |
| `XF86MonBrightnessDown` | `desktop-shell brightness down` | Lower brightness |

The spatial switcher commits its current selection when either Alt key is
released. Bind the modifier keys with a release target and make those bindings
transparent:

```lua
hl.bind("ALT + ALT_L", hl.dsp.exec_cmd("desktop-shell alttab commit"), {
  release = true,
  transparent = true,
  ignore_mods = true,
})
hl.bind("ALT + ALT_R", hl.dsp.exec_cmd("desktop-shell alttab commit"), {
  release = true,
  transparent = true,
  ignore_mods = true,
})
```

## Hyprland Lua example

This fragment is intentionally limited to Desktop Shell actions. Keep
application, workspace, monitor, and layout policy in the surrounding Hyprland
configuration.

```lua
local function shell(command)
  return hl.dsp.exec_cmd("desktop-shell " .. command)
end

hl.bind("ALT + SPACE", shell("launcher toggle"))
hl.bind("SUPER + N", shell("toggle"))
hl.bind("SUPER + V", shell("clipboard open"))
hl.bind("SUPER + W", shell("pick"))
hl.bind("SUPER + slash", shell("cheatsheet toggle"))
hl.bind("SUPER + L", shell("lock"))

hl.bind("ALT + TAB", shell("alttab next"))
hl.bind("ALT + SHIFT + TAB", shell("alttab prev"))
hl.bind("ALT + ALT_L", shell("alttab commit"), {
  release = true,
  transparent = true,
  ignore_mods = true,
})
hl.bind("ALT + ALT_R", shell("alttab commit"), {
  release = true,
  transparent = true,
  ignore_mods = true,
})

hl.bind("ALT + left", shell("direction l"))
hl.bind("ALT + right", shell("direction r"))
hl.bind("ALT + up", shell("direction u"))
hl.bind("ALT + down", shell("direction d"))

hl.bind("XF86AudioRaiseVolume", shell("volume up"), { repeating = true })
hl.bind("XF86AudioLowerVolume", shell("volume down"), { repeating = true })
hl.bind("XF86AudioMute", shell("volume mute"))
hl.bind("XF86MonBrightnessUp", shell("brightness up"), { repeating = true })
hl.bind("XF86MonBrightnessDown", shell("brightness down"), { repeating = true })
```

If the keyboard emits different key names, use `wev` and bind the reported
symbols. See the current
[Hyprland bind documentation](https://wiki.hypr.land/Configuring/Basics/Binds/)
for additional flags and keycode bindings.

## Workspace bindings

The workspace list is configurable, but Desktop Shell does not generate
compositor workspace bindings. Keep both sides aligned: every configured
workspace should be reachable from Hyprland, and a configured scrolling
workspace must be present in that list.

For example:

```lua
hl.bind("SUPER + 1", hl.dsp.focus({ workspace = 1 }))
hl.bind("SUPER + 2", hl.dsp.focus({ workspace = 2 }))
hl.bind("SUPER + SHIFT + 1", hl.dsp.window.move({ workspace = 1, follow = false }))
hl.bind("SUPER + SHIFT + 2", hl.dsp.window.move({ workspace = 2, follow = false }))
```

The shell reads live workspace state from Hyprland; it does not intercept these
bindings.
