# Desktop Shell

A keyboard-first Hyprland desktop shell built with Quickshell and packaged as a
Nix flake.

Desktop Shell treats the bar, launcher, control center, lock screen, and window
navigation as one coherent interface. It follows live compositor and system
services instead of maintaining a second desktop state database.

## Features

- Output-aware bar with workspaces, tray, calendar, battery, audio, metrics,
  recording status, and configurable network controls.
- Launcher with separate application-launch and existing-window focus modes,
  usage-aware ordering, and optional Firefox-compatible tab search.
- Spatial Alt-Tab overview with live workspace previews, directional
  navigation, drag-to-workspace, and scrolling-layout geometry.
- Control center with notification history, persistent NetworkManager Wi-Fi
  state, BlueZ device management, brightness and power controls, and a
  per-stream PipeWire mixer.
- Clipboard history, wallpaper picker, lock screen, media-change notifications,
  focus mode, and a generated keybinding reference.
- One `desktop-shell` command for systemd lifecycle, diagnostics, UI actions,
  and compositor keybindings.
- Typed Home Manager configuration and a small NixOS module for PAM lock
  integration.

## Requirements

Desktop Shell currently supports Hyprland on NixOS or another Nix-managed Linux
system. Its runtime integration expects:

- a UWSM-managed Wayland session;
- systemd user services;
- NetworkManager for the Wi-Fi page;
- PipeWire for audio controls;
- BlueZ for Bluetooth controls;
- `hyprpaper` for wallpaper application.

Individual surfaces degrade when their service or hardware is absent. For
example, brightness uses a kernel backlight when available and can fall back to
DDC/CI when the monitor and system expose it.

## Installation

Use the flake's Home Manager module for the user service and configuration. On
NixOS, also import its NixOS module to create the PAM service used by the lock
screen.

See [Installation](docs/installation.md) for a complete flake example and
[Configuration](docs/configuration.md) for the option reference.

After activation:

```console
$ desktop-shell status
$ desktop-shell doctor
```

Desktop Shell deliberately does not install a keybinding policy. Connect its
commands to the bindings already owned by your Hyprland configuration; a
working set is documented in [Keybindings](docs/keybindings.md).

## Documentation

- [Installation](docs/installation.md)
- [Configuration](docs/configuration.md)
- [Commands](docs/commands.md)
- [Keybindings](docs/keybindings.md)
- [Browser tabs](docs/browser-tabs.md)
- [Architecture](docs/architecture.md)
- [Contributing](CONTRIBUTING.md)

## Development

```console
$ nix develop
$ nix flake check
$ nix build
```

See [Contributing](CONTRIBUTING.md) before changing backend contracts, runtime
dependencies, or compositor integration.

## License

[GPL-3.0-or-later](LICENSE)
