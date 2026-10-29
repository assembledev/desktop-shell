# User guide

The examples below use the [suggested keybindings](keybindings.md). Bindings
belong to your Hyprland configuration; the shell also exposes each action
through the [command line](commands.md).

## Open an application or find a window

Press **Alt+Space** to open the launcher. Type an application's name, select a
result with **Up/Down** or **Ctrl+K/J**, and press **Enter** to launch it.
**Escape** closes the launcher.

**Tab** switches between **Launch** and **Focus**:

- **Launch** opens a new application instance. Frequently launched applications
  move up the list.
- **Focus** finds existing windows by application or window title. **Enter**
  switches to that window; **Ctrl+Enter** opens a new instance of its application.

In Launch mode, type **@** to list configured launch profiles. Selecting one
opens missing applications and moves matching windows to the profile's
workspaces. Set profiles in [Configuration](configuration.md#launch-profiles).

With [browser tabs](browser-tabs.md) enabled, Focus also searches inactive tabs.
Start a query with **!** to search only tabs. **Enter** activates the selected tab
and its browser window.

## Switch and move windows

Hold **Alt** and press **Tab** to open the workspace overview. Press Tab again
to advance, or **Shift+Tab** to go back. Use the **arrow keys** or **H/J/K/L**
to select spatially. Release Alt or press **Enter** to focus the selected window.
Clicking outside the overview cancels it.

Drag a window preview onto another workspace to move it. The overview follows
the workspace arrangement in
[`workspaces.items`](configuration.md#workspaces), including its two-dimensional
coordinates. Workspace buttons on the bar switch directly to that workspace.

The optional [pop-out bindings](keybindings.md#window-pop-outs) turn a window
into a pinned floating window and return it to tiling when toggled again.

## Use the bar and control center

Click the **clock** for the calendar, the **network icon** for connection
details, the **notification bell** for the control center, and the **power
icon** for lock, suspend, restart, and shutdown. **Super+N** also opens the
control center. Opening it from the bar or **Super+N** starts at the overview.
The network details shortcut opens its Wi-Fi page directly.

The control center groups quick controls above notification history. Wi-Fi,
Bluetooth, Display, and Sound open their detailed pages:

- **Wi-Fi:** choose a network and enter its password when requested.
- **Bluetooth:** pair or connect devices. Nearby discovery runs while the page
  is open; paired devices can reconnect after it closes.
- **Sound:** choose input and output devices, set levels, and control individual
  playback or recording streams. The bar's microphone badge shows when an
  application is using an audio source; hover it for application names.
- **Display:** drag displays into position, choose modes and scales, or select
  a layout preset. Test the layout, then choose **Keep** within 20 seconds;
  otherwise the previous layout returns. Confirmed layouts are remembered for
  that set of displays.

Network details include addresses, DNS, link rate, and live traffic. Click an
address to copy it. Opening this panel also queries `ip.me` for the public IP
address through your current connection. See [network commands](commands.md#network)
for refresh intervals and data sources.

**Do Not Disturb** silences notification popups and sounds while retaining
history. **Focus** hides the bar. These settings survive shell restarts. To
bring back a hidden bar from a terminal:

```console
$ desktop-shell focus off
```

Opening a bar popup closes the previous one. **Escape** closes the calendar,
Control Center, network, Tailscale, or power popup before dismissing toasts.
With no bar popup open, it dismisses notification and Now Playing popups.
Use Control Center's back button to return from a detail page to the overview.

## Clipboard and wallpapers

Press **Super+V** to search clipboard history. Use the arrow keys to select an
entry and **Enter** to copy it, then paste normally in your application. Clicking
an entry also copies it. Links stay text; selecting one does not open a browser.
Text and image history are stored locally by cliphist. To clear that history:

```console
$ desktop-shell clipboard wipe
```

Press **Super+W** for the wallpaper picker. Type to filter file names, use
**Left/Right** or **H/L** to browse, and press **Enter** to apply an image.
**Escape** cancels. Add images to the configured
[wallpaper directory](configuration.md#wallpaper); its default is `~/Wallpapers`.

## Lock the session

Press **Super+L**, or choose **Lock** from the power menu. Enter your account
password to unlock. Locking uses the NixOS PAM integration installed with the
shell's system module.

Automatic locking and locking before suspend belong to your idle manager.
Configure those separately; [Session lock](lock-security.md#system-integration)
describes the Hypridle integration.

## Multiple displays

By default, each connected display gets a bar. Keyboard actions open on the
display that has Hyprland focus; clicking a bar opens its menus on that display.
Notifications appear once on the focused display and stay there until dismissed.

The wallpaper choice is shared across displays. Configure workspace placement
and monitor rules in Hyprland, and use the shell's Display page for interactive
layout changes.

## Make it yours

The first useful options are [workspaces](configuration.md#workspaces),
[wallpapers](configuration.md#wallpaper),
[keyboard labels](configuration.md#keyboard-layout-labels), and
[theme](configuration.md#theme). Optional network providers and launch profiles
can be added later. **Super+/** opens the keybinding reference populated by your
`integrations.hotkeys` entries.
