# Desktop Shell

A keyboard-first desktop shell for Hyprland, built with Quickshell.

A bar, launcher, spatial window switcher, control center, clipboard history,
wallpaper picker, and lock screen that work together. Desktop Shell reads live
state from Hyprland and the desktop's services. NixOS and Home Manager handle
installation and configuration.

https://github.com/user-attachments/assets/14bcbe04-3493-41c1-a380-b65dd58fe4a0

## Install

The supported setup is **NixOS, Home Manager, and Hyprland with Lua
configuration**, launched through UWSM. Start with an existing Hyprland session.

Follow the [installation guide](docs/installation.md), then the
[user guide](docs/user-guide.md). The shell supplies its own compositor
integration; your applications, workspace bindings, monitor rules, and login
manager stay in your configuration.

## What it does

- A bar on each display, with workspaces, tray, calendar, audio, battery, system
  metrics, and network status.
- An application launcher with a separate search for open windows, launch
  profiles, and optional browser-tab search.
- A spatial Alt-Tab overview with live workspace previews and drag-to-workspace.
- A control center for notifications, Wi-Fi, Bluetooth, PipeWire audio, displays,
  brightness, and power controls.
- Clipboard search, a wallpaper picker, media notifications, focus mode, and a
  keybinding reference.
- A separate PAM-backed lock screen and an optional greetd login screen.

NetworkManager supplies Wi-Fi controls, PipeWire supplies audio, BlueZ supplies
Bluetooth, and hyprpaper applies wallpapers. Hardware controls appear as their
backends become available. Tailscale and browser tabs are optional integrations.

## Documentation

- [Installation](docs/installation.md) — modules, prerequisites, and first login
- [User guide](docs/user-guide.md) — everyday controls and keyboard navigation
- [Configuration](docs/configuration.md) — Home Manager options
- [Keybindings](docs/keybindings.md) — suggested Hyprland bindings
- [Commands](docs/commands.md) — CLI reference
- [Troubleshooting](docs/troubleshooting.md) — diagnostics and removal
- [Browser tabs](docs/browser-tabs.md) · [Login greeter](docs/greeter.md) ·
  [Session lock](docs/lock-security.md)

For contributors: [Contributing](CONTRIBUTING.md),
[Architecture](docs/architecture.md), and [Design notes](DESIGN.md).

## Development

```console
$ nix develop
$ nix flake check
$ nix build --quiet
```

## License

[GPL-3.0-or-later](LICENSE)
