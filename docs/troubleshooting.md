# Troubleshooting

Start in a terminal inside the Hyprland session:

```console
$ desktop-shell doctor
$ desktop-shell status
$ desktop-shell logs
```

`doctor` checks the configuration and compositor connection. `status` and `logs`
inspect the systemd user service. For live logs, use `desktop-shell logs --follow`.

## The shell does not start

Check that the session was launched through UWSM and that its graphical target
is active:

```console
$ systemctl --user is-active graphical-session.target
$ systemctl --user show-environment | grep -E 'WAYLAND_DISPLAY|HYPRLAND_INSTANCE_SIGNATURE'
$ hyprctl version
```

Choose **Hyprland (uwsm-managed)** in your login manager, or use
`uwsm start hyprland.desktop` from a text login. After changing session setup,
log out and back in. With UWSM, Home Manager's Hyprland systemd integration must
be disabled; see [Installation](installation.md#session-and-system-services).

Once the session is active, run `desktop-shell start`. If repeated startup
failures hit systemd's start limit, inspect the logs, fix the reported error,
then run:

```console
$ systemctl --user reset-failed desktop-shell.service
$ desktop-shell start
```

## The bar is hidden or appears twice

Run `desktop-shell focus off` to leave focus mode. An
[`output`](configuration.md#module-options) restriction may also select a
different display.

Duplicate bars usually mean a second shell instance was launched manually or
from Hyprland startup commands. The Home Manager service owns startup. Remove
the extra launch command and stop any foreground instance. Also disable the
previous bar and notification daemon when replacing them with Desktop Shell.

## A shortcut does nothing

First run its `desktop-shell` command in a terminal. If the command works,
check your [Hyprland bindings](keybindings.md) and inspect `hyprctl binds`.
If Alt-Tab never commits, include the Alt release bindings from that page.

Escape handling and window pop-outs require the shell's
[Lua integration](installation.md#hyprland-integration). Home Manager loads it
when it manages Hyprland; an external compositor configuration needs the loader
shown in the installation guide.

## Applications do not launch

The launcher reads installed desktop entries and launches them through UWSM.
Check that the application has a visible `.desktop` entry and that the UWSM
session is running. Test its desktop-entry ID directly, for example:

```console
$ uwsm app -- firefox.desktop
```

For a launch profile, check its configured entry IDs and workspaces with
`desktop-shell profile status-json <name>`.

## Wi-Fi, Bluetooth, audio, or wallpapers are unavailable

Check the backend for the affected control:

| Control | What to check |
| --- | --- |
| Wi-Fi | NetworkManager is enabled and manages the wireless interface |
| Bluetooth | BlueZ is enabled, the adapter is powered, and one pairing agent is running |
| Audio | PipeWire and WirePlumber are running in the user session |
| Wallpaper | hyprpaper is running and the configured directory contains images |
| Laptop brightness | A kernel backlight is exposed to brightnessctl |
| Monitor brightness | DDC/CI is enabled in the monitor and the user can access its I2C device |

The package supplies client tools; the system supplies daemons and device
permissions. See [system services](installation.md#session-and-system-services).
For browser-tab failures, use the [bridge diagnostics](browser-tabs.md#installation).

## The lock rejects the correct password

Check that the NixOS module is enabled and that
`/etc/pam.d/desktop-shell-lock` exists. Inspect the locker journal from an
already authenticated terminal:

```console
$ journalctl --user -b -u desktop-lock.service
```

The lock expects password authentication. Custom PAM conversations may need
additional UI support. See [Session lock](lock-security.md) for recovery and
compositor requirements.

## Report a problem

Include the action that failed, the visible result, your NixOS and Hyprland
versions, and relevant `doctor` output and log lines. For display problems,
include the affected outputs and scales. Review logs before posting them;
window titles, device names, and network details can contain personal data.

## Remove Desktop Shell

Remove shell-specific keybindings and any manual Lua loader. Set
`programs.desktop-shell.enable = false` in Home Manager and rebuild your
configuration. If you use the optional greeter, configure your replacement
login method before disabling the NixOS integration. The next login uses your
remaining desktop configuration.

Disabling the module leaves user data in
`${XDG_STATE_HOME:-~/.local/state}/desktop-shell` and cliphist's own database.
Wallpaper images remain in their original directory. Clear clipboard history
with `desktop-shell clipboard wipe` before removing the package if you want to
remove those entries as well.
