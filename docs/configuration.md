# Configuration

The Home Manager module is configured below `programs.desktop-shell`. It writes
the resolved runtime configuration to:

```text
$XDG_CONFIG_HOME/desktop-shell/config.json
```

The file is generated; change the Nix options rather than editing it. Inspect
the active path and JSON with `desktop-shell config path` and
`desktop-shell config show`.

## Minimal configuration

```nix
{
  programs.desktop-shell.enable = true;
}
```

This installs the package, enables `desktop-shell.service`, starts clipboard
watchers and the Blueman pairing agent, and uses the built-in five-workspace
layout. The bar has no third-party network controls and browser-tab search is
disabled.

## Module options

| Option | Default | Description |
| --- | --- | --- |
| `enable` | `false` | Install and configure Desktop Shell |
| `package` | `null` | Package override; `null` builds the package from the module source |
| `hyprlandPackage` | `pkgs.hyprland` | Package providing the `hyprctl` placed on the backend path |
| `finalPackage` | read-only | Resolved package used by the module |
| `systemd.enable` | `true` | Enable the user service |
| `systemd.target` | `"graphical-session.target"` | User target that owns shell services |
| `output` | `null` | Output name for shell surfaces; `null` uses the first screen reported by Quickshell |
| `clipboard.watch.enable` | `true` | Store text and image clipboard changes with `cliphist` |
| `bluetooth.agent.enable` | `true` | Run Blueman as a pairing agent without its tray providers |

Set `hyprlandPackage` when the session uses a pinned or patched Hyprland build.
This keeps the packaged `hyprctl` compatible with the running compositor.

The service target must be part of the Wayland session and carry
`WAYLAND_DISPLAY`. Most UWSM and Home Manager Hyprland sessions already expose
`graphical-session.target` for this purpose.

## Workspaces

`workspaces.items` is the ordered topology consumed by the bar, launcher, and
window switcher. Each item has:

| Field | Type | Meaning |
| --- | --- | --- |
| `id` | positive integer | Hyprland workspace ID |
| `label` | string | Label rendered in shell surfaces |
| `x` | integer | Horizontal coordinate for spatial navigation |
| `y` | integer | Vertical coordinate; defaults to `0` |

IDs must be unique. `workspaces.scrolling`, when set, must name one of those
IDs.

```nix
programs.desktop-shell = {
  workspaces = {
    items = [
      { id = 1; label = "web";  x = 0; y = 0; }
      { id = 2; label = "code"; x = 1; y = 0; }
      { id = 3; label = "chat"; x = 2; y = 0; }
      { id = 4; label = "lab";  x = 1; y = 1; }
    ];
    scrolling = 2;
  };
};
```

Desktop Shell does not create Hyprland workspace rules or bindings. Configure
the same IDs in the compositor.

## Wallpaper

| Option | Default | Description |
| --- | --- | --- |
| `wallpaper.directory` | `$HOME/Wallpapers` | Directory scanned recursively by the picker |
| `wallpaper.default` | `null` | Image copied to `wallpaper.jpg` when that seed file is absent |

```nix
programs.desktop-shell.wallpaper = {
  directory = "${config.home.homeDirectory}/Pictures/Wallpapers";
  default = ./wallpaper.jpg;
};
```

The current selection is stored below
`$XDG_STATE_HOME/desktop-shell/wallpaper/`. `hyprpaper` must be running; the
module does not take ownership of its monitor policy.

## Bar

| Option | Default | Description |
| --- | --- | --- |
| `bar.compact` | `false` | Reduce spacing in the landscape bar |
| `bar.showVram` | `true` | Show VRAM metrics when available |
| `bar.workspaceIcons` | `true` | Show application icons in workspace controls |
| `bar.networkControls` | `[]` | Ordered generic status/toggle providers |

## Keyboard layout labels

`keyboard.layoutLabels` is an ordered list of short display labels. Its indexes
must match the compositor's configured keyboard layout order. Desktop Shell
does not embed a language or country dictionary; the neutral default is
`[ "EN" ]`.

```nix
programs.desktop-shell.keyboard.layoutLabels = [ "EN" ];
```

### Network controls

A provider is trusted Nix configuration, not a plugin downloaded by the shell:

| Field | Type | Meaning |
| --- | --- | --- |
| `id` | string | Unique ID matching `[A-Za-z0-9_.-]+` |
| `label` | string | Text used before the first status result |
| `icon` | string | Optional local path or image URL understood by QML |
| `statusCommand` | list of strings | Non-empty argv returning a JSON object |
| `toggleCommand` | list of strings | Non-empty argv that toggles the provider |

The status object accepts `text`, `active`, and `login` fields:

```json
{"text":"VPN","active":true,"login":false}
```

Commands are executed directly as argv; shell syntax is not interpreted. Use
Nix store paths for reproducible providers:

```nix
{ pkgs, ... }:
let
  networkStatus = pkgs.writeShellApplication {
    name = "example-network-status";
    runtimeInputs = [ pkgs.jq pkgs.systemd ];
    text = ''
      if systemctl --user --quiet is-active example-tunnel.service; then
        active=true
      else
        active=false
      fi
      jq -nc --argjson active "$active" \
        '{ text: "Private", active: $active, login: false }'
    '';
  };
  networkToggle = pkgs.writeShellApplication {
    name = "example-network-toggle";
    runtimeInputs = [ pkgs.systemd ];
    text = ''
      if systemctl --user --quiet is-active example-tunnel.service; then
        systemctl --user stop example-tunnel.service
      else
        systemctl --user start example-tunnel.service
      fi
    '';
  };
in
{
  programs.desktop-shell.bar.networkControls = [
    {
      id = "private-network";
      label = "Private";
      statusCommand = [ "${networkStatus}/bin/example-network-status" ];
      toggleCommand = [ "${networkToggle}/bin/example-network-toggle" ];
    }
  ];
}
```

Desktop Shell does not add sudo policy for providers. Keep any elevated helper
narrow and declare it in the surrounding NixOS configuration.

## Browser tabs

| Option | Default | Description |
| --- | --- | --- |
| `browserTabs.enable` | `false` | Read the optional Firefox-compatible tab bridge |
| `browserTabs.desktopEntryId` | `"firefox"` | Browser desktop-entry ID used to match windows |
| `browserTabs.displayName` | `"Firefox"` | Name shown in launcher messages |
| `browserTabs.icon` | `"firefox"` | Theme icon used for tab results |

Enabling the option configures the shell side. The browser still needs the
extension and native messaging host described in
[Browser tabs](browser-tabs.md).

## Lock screen

`lock.keyboardLayoutIndex` is either `null` or a non-negative layout index. The
default `null` preserves the active keyboard layout. A configured index is
selected before locking and the prior layout is restored after unlock.

```nix
programs.desktop-shell.lock.keyboardLayoutIndex = 0;
```

The lock requires the PAM service from `nixosModules.default`; see
[Installation](installation.md).

## Integrations

These options connect Desktop Shell to policy owned by the surrounding system:

| Option | Default | Contract |
| --- | --- | --- |
| `integrations.hotkeys` | `[]` | Entries displayed in the built-in cheat sheet |
| `integrations.privilegedHelper` | `null` | Fixed-purpose helper invoked through the system sudo wrapper |
| `integrations.recordingStateFile` | `null` | File containing a recording start timestamp in Unix seconds |
| `integrations.sddmWallpaperSync` | `null` | Command invoked with the selected wallpaper path |

A relative `recordingStateFile` is resolved below `XDG_RUNTIME_DIR`; an absolute
path is used as written. Removing the file hides the bar indicator.

Hotkey entries have `key`, `title`, and optional `category`, `description`, and
`hidden` fields:

```nix
programs.desktop-shell.integrations.hotkeys = [
  {
    key = "ALT + SPACE";
    title = "Launcher";
    category = "Shell";
  }
  {
    key = "ALT_L";
    title = "Commit Alt-Tab";
    category = "Internal";
    hidden = true;
  }
];
```

`privilegedHelper` is a low-level integration point used by platform-profile
controls. Its executable and sudo policy are intentionally not generated by
the Home Manager module.

## Theme

`theme` is a typed color set with a complete built-in dark palette. Override
only the values that differ:

```nix
programs.desktop-shell.theme = {
  fontFamily = "FiraCode Nerd Font";
  bgSolid = "#10131c";
  text = "#d8dee9";
  blue = "#88c0d0";
  purple = "#b48ead";
};
```

`fontFamily` is a fontconfig family name; install that font in the user
profile. Color values use Qt hexadecimal form: `#RRGGBB` or `#AARRGGBB`. The
available fields are:

```text
fontFamily bgSolid bgRaised bgMuted bgHover bgHoverAlt bgToast selectedBg
foreground text muted mutedAlt blue terminalBlue green yellow orange
red brightRed purple
surfaceGlass surfaceGlassStrong surfaceScrim surface surfaceBar
surfaceRaised surfaceSoft surfaceHover surfaceMuted surfaceMutedHover
surfaceAccent surfaceToast borderSubtle
```

Surface colors include their opacity. When changing the base palette, update
the corresponding surface values as well; they are explicit colors rather than
being recomputed from a base color at Home Manager evaluation time.
