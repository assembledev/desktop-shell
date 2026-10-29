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
disabled. The module also installs its
[Hyprland integration](installation.md#hyprland-integration); Home Manager-managed
Hyprland must use Lua configuration.

## Module options

| Option | Default | Description |
| --- | --- | --- |
| `enable` | `false` | Install and configure Desktop Shell |
| `package` | `null` | Package override; `null` builds the package from the module source |
| `hyprlandPackage` | `pkgs.hyprland` | Package providing the `hyprctl` placed on the backend path |
| `tailscalePackage` | `pkgs.tailscale` | Client installed and used for the built-in Tailscale network control |
| `finalPackage` | read-only | Resolved package used by the module |
| `systemd.enable` | `true` | Enable the user service |
| `systemd.target` | `"graphical-session.target"` | User target that owns shell services |
| `output` | `null` | Restrict bars to one output; `null` shows a bar on every output. An unavailable named output falls back to the first available screen |
| `display.startupLayout` | `[]` | Declarative monitor rules shown as the exact restore target in display settings |
| `launcher.profiles` | `{}` | Named application layouts with labels and icons |
| `launcher.autoStartProfile` | `null` | Profile applied at graphical session startup |
| `clipboard.watch.enable` | `true` | Store text and image clipboard changes with `cliphist` |
| `bluetooth.agent.enable` | `true` | Run Blueman as a pairing agent without its tray providers |

Set `hyprlandPackage` when the session uses a pinned or patched Hyprland build.
This keeps the packaged `hyprctl` compatible with the running compositor.

The service target must belong to the UWSM session and carry
`WAYLAND_DISPLAY`. The default `graphical-session.target` is used by the
[installation example](../examples/home.nix).

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

## Launch profiles

Profiles contain desktop entry file IDs and their target workspaces. Desktop
Shell derives window identity from standard desktop-entry metadata such as
`StartupWMClass`, the desktop-entry ID, and the executable name; profile
configuration does not duplicate compositor classes.

```nix
programs.desktop-shell.launcher = {
  profiles.work = {
    label = "Work";
    icon = "applications-office";
    applications = [
      {
        id = "firefox.desktop";
        workspace = 2;
      }
      {
        id = "org.wezfurlong.wezterm.desktop";
        workspace = 1;
      }
    ];
  };
  autoStartProfile = "work";
};
```

Select profiles with `@<name>` in the launcher. `autoStartProfile` applies
once per graphical session. Missing applications launch on their target
workspaces; matching windows move there without switching your visible
workspace. Repeated requests while an application is opening share the pending
launch. See [profile commands](commands.md#launcher) to inspect placement or
wait for completion.

`label` defaults to the profile ID. `description` is optional and otherwise
lists the resolved application names. `icon` is an optional freedesktop icon
name; a missing icon falls back to the first application's icon. Profile names
must match `[a-z0-9][a-z0-9-]*`.
Desktop entry IDs must end in `.desktop`; duplicates within a profile are
rejected. Target workspaces must exist in `workspaces.items`, and
`autoStartProfile` must name a configured profile.

## Displays

`display.startupLayout` describes the compositor-owned monitor rules restored
by the display page. Each entry accepts `output`, `mode`, `position`, `scale`,
and optional `bitdepth`, matching Hyprland's monitor rule fields. Desktop Shell
shows these values before offering **Restore startup layout**; it does not use
this option to generate a second set of compositor rules.

```nix
programs.desktop-shell.display.startupLayout = [
  {
    output = "eDP-1";
    mode = "preferred";
    position = "0x0";
    scale = 2;
  }
];
```

When another module already owns the monitor list, assign that list directly
to this option rather than duplicating it.

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

## Multiple displays

Bars appear on every output by default. Keyboard actions open surfaces on the
compositor-focused output; bar clicks open them on that bar's output. Open
surfaces stay there until closed. Notifications and OSD appear once on the
focused output at the time of the event.

Hotplug adds and removes output presentations without restarting the shell.
Disconnecting an output closes its surfaces and removes its transient items.
`output` restricts bars and provides a fallback when compositor focus is
unavailable; keyboard actions still follow focus. Wallpaper selection is
session-wide.

## Bar

| Option | Default | Description |
| --- | --- | --- |
| `bar.compact` | `false` | Select the compact landscape spacing density while preserving the bar's group hierarchy |
| `bar.showVram` | `true` | Show VRAM metrics when available |
| `bar.workspaceIcons` | `true` | Show application icons in workspace controls |
| `bar.networkControls` | `[]` | Ordered generic status/toggle providers |

On narrow displays the bar shortens the clock and workspace title, folds tray
items into an overflow shelf, then hides optional network labels as needed.
Compact mode uses denser landscape spacing; portrait displays retain larger
actions. Shared spacing and theme owners are described in
[Design notes](../DESIGN.md).

## Keyboard layout labels

`keyboard.layoutLabels` is an ordered list of short display labels. Its indexes
must match the compositor's configured keyboard layout order. Desktop Shell
does not embed a language or country dictionary; the neutral default is
`[ "EN" ]`.

```nix
programs.desktop-shell.keyboard.layoutLabels = [ "EN" ];
```

### Network controls

`bar.networkControls` is an ordered list of trusted providers. The default `[]`
creates no network controls and performs no Tailscale polling or backend calls;
no Tailscale daemon or CLI is required in that configuration.

Each provider has a unique `id` matching `[A-Za-z0-9_.-]+`, a `label` and an
optional `icon` path or QML image URL. Select one complete mode:

| Mode | Required fields | Status and toggle behavior |
| --- | --- | --- |
| Tailscale | `id = "tailscale"`, no command or unit fields | Built-in LocalAPI status and CLI up/down |
| System service | `unit`, `startCommand`, `stopCommand`, `retryCommand` | Systemd status and the action selected for its state |
| Custom commands | `statusCommand`, `toggleCommand` | Execute the supplied argv pair |

Do not mix modes or supply only half a command pair. Service actions are all
required, even when they invoke the same command. Invalid configurations fail
before executing provider commands.

#### Tailscale

```nix
programs.desktop-shell.bar.networkControls = [
  { id = "tailscale"; label = "Tail"; }
];
```

Home Manager installs and uses `tailscalePackage` for this built-in provider. Set it to
the package used by the surrounding system when its Tailscale version is pinned.
For configurations managed without Home Manager, make the CLI available on the
shell service's PATH.

The existing `tailscaled.service` and LocalAPI socket supply status. The socket
is normally `/var/run/tailscale/tailscaled.sock`; set
`DESKTOP_SHELL_TAILSCALE_SOCKET` in the service environment for another location.
A running daemon uses the user's existing operator permissions for `tailscale up`
and `down`, with bounded command timeouts. Starting an inactive daemon requires
an explicitly configured `integrations.privilegedHelper` that permits the fixed
`tailscaled-start` action. Without that authority, startup fails.

Desktop Shell does not install or enable the daemon, enroll devices, configure
routing or credentials, or grant sudo access. Those belong to the surrounding
system. Authentication requirements are shown by the provider; complete enrollment
through the system's Tailscale workflow.

The `tailscale` ID also exposes the peer/Taildrop panel. An explicit custom
`statusCommand` and `toggleCommand` pair may use that ID: the supplied commands
control its toggle, while the peer panel still reads LocalAPI with the user's
daemon permissions. See [Tailscale commands](commands.md#tailscale-peers-and-taildrop)
for refresh and transfer behavior.

#### System services

Use a service provider when the connection is represented by a system unit:

```nix
{ pkgs, ... }:
{
  programs.desktop-shell.bar.networkControls = [
    {
      id = "work";
      label = "Work";
      unit = "example-vpn.service";
      startCommand = [ "${pkgs.systemd}/bin/systemctl" "--no-ask-password" "start" "example-vpn.service" ];
      stopCommand = [ "${pkgs.systemd}/bin/systemctl" "--no-ask-password" "stop" "example-vpn.service" ];
      retryCommand = [ "${pkgs.systemd}/bin/systemctl" "--no-ask-password" "restart" "example-vpn.service" ];
    }
  ];
}
```

The surrounding system must authorize those actions. Commands can instead call
an existing fixed-purpose helper. Desktop Shell adds no privilege policy.

Status uses system scope and derives text/tooltips from the label and unit state.
Clicking an active unit runs `stopCommand`, an inactive unit runs `startCommand`,
and a failed unit runs `retryCommand`. Clicks during activation/deactivation are
rejected. For a user service, use a custom command pair that explicitly selects
`systemctl --user`.

#### Custom commands

`statusCommand` returns a JSON object; `toggleCommand` changes provider state.
The status object accepts `text`, `active`, `login` and an optional `tooltip`:

```json
{"text":"Private","active":true,"login":false,"tooltip":"Private network connected"}
```

Every command is a literal argv list. Shell syntax is not interpreted; use Nix
store paths for reproducible executables. The backend validates each complete
argv list before execution. Commands own their own authentication and state
semantics.

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
[Installation](installation.md). Lock triggers, authentication policy, and recovery
requirements are described in [Session-lock security](lock-security.md).

## Integrations

These options connect Desktop Shell to policy owned by the surrounding system:

| Option | Default | Contract |
| --- | --- | --- |
| `integrations.hotkeys` | `[]` | Entries displayed in the built-in cheat sheet |
| `integrations.privilegedHelper` | `null` | Fixed-purpose helper invoked through the system sudo wrapper |
| `integrations.recordingStateFile` | `null` | File containing a recording start timestamp in Unix seconds |
| `integrations.loginWallpaperSync` | `null` | Command invoked with the selected wallpaper path to update a login greeter cache |

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

`theme` provides typed colors and font families with a complete built-in dark
palette. Override only the values that differ:

```nix
programs.desktop-shell.theme = {
  uiFontFamily = "Fira Sans";
  fontFamily = "FiraCode Nerd Font";
  bgSolid = "#10131c";
  textPrimary = "#e7eaf2";
  textSecondary = "#b7becd";
  accent = "#a78bfa";
};
```

`uiFontFamily` controls UI text throughout the shell: bar labels, search and
input fields, menus, calendars, notifications, device pages, the switcher,
wallpaper picker, keybinding reference, media and lock
surfaces. Its default is `Fira Sans`; fontconfig resolves the selected family.
`fontFamily` retains the icon-font role for existing Nerd Font glyphs; authored
vector symbols do not depend on it. Install any specifically named font in the
user profile.

To use sans-serif for all UI text, override just
`programs.desktop-shell.theme.uiFontFamily = "sans-serif";`.

Color values use Qt hexadecimal form: `#RRGGBB` or `#AARRGGBB`. The available
fields are:

```text
fontFamily uiFontFamily bgSolid bgRaised bgMuted bgHover bgHoverAlt bgToast selectedBg
textPrimary textSecondary textMuted textDisabled textOnAccent
accent accentHover info special resource utility
success warning caution danger dangerStrong
border borderMuted
surfaceGlass surfaceGlassStrong surfaceScrim surface surfaceBar
surfaceRaised surfaceSoft surfaceHover surfaceMuted surfaceMutedHover
surfaceAccent surfaceToast borderSubtle
```

Surface colors include their opacity. When changing the base palette, update
the corresponding surface values as well; they are explicit colors rather than
being recomputed from a base color at Home Manager evaluation time.

See [Design notes](../DESIGN.md) for semantic roles and visual principles.
