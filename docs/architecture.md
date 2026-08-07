# Architecture

Desktop Shell is a Quickshell process with a packaged command backend. Nix
builds both from the same source tree and supplies immutable paths and typed
configuration at launch time.

## Runtime model

The Home Manager module installs `desktop-shell.service` as a systemd user
unit. The service runs:

```console
$ desktop-shell run
```

`run` exports the generated configuration and starts `src/shell.qml` with
Quickshell. The entry point owns the long-lived shell surfaces:

- bar, tray, workspaces, calendar, and an optional recording indicator;
- launcher and existing-window focus search;
- control center, notification server, Wi-Fi, Bluetooth, and audio mixer;
- clipboard history and wallpaper picker;
- spatial window switcher with workspace previews;
- lock preview, media notifications, and keybinding reference.

The lock screen also has a small standalone entry point at `src/lock.qml`.
Keeping it separate allows the PAM lock process to have a narrower lifetime
than the desktop shell.

## Ownership boundaries

### QML

`src/modules/` owns presentation, interaction state, and Quickshell-native
models. Components consume configuration passed by the package; they do not
select machine names, output identifiers, applications, or network providers.

Hyprland is the supported compositor backend. Workspace and window operations
are centralized in the Hyprland integration so UI components do not each grow
their own dispatch vocabulary. The adapter targets Hyprland's Lua dispatcher
API. Supporting another compositor would require a complete integration with
equivalent focus, workspace, layer-shell, and screencopy behavior.

### Command backend

`src/backend/desktop-shell.sh` is the stable command entry point used by
keybindings and QML subprocesses. Cohesive operations live in
`src/backend/lib/`; the dispatcher remains a routing layer.

The backend owns operations that are a poor fit for QML, including launcher
activation through UWSM, wallpaper application, clipboard decoding, device
commands, runtime environment discovery, and compact JSON snapshots. JSON
written for QML is an interface: change its producer and consumer together.

### Nix package

`nix/package.nix` assembles the immutable QML tree, backend, bundled defaults,
and runtime dependencies. It also provides the executable wrapper. A command
used by the backend must be present here rather than assumed to exist in the
interactive shell.

### Home Manager module

The Home Manager module owns user policy, generated configuration, package
installation, state directories, and the systemd user service. It does not own
Hyprland keybindings. Bind commands from the compositor configuration so the
same package remains usable with an existing Hyprland setup.

### NixOS module

The NixOS module owns system integration that Home Manager cannot provide. In
particular, it creates the PAM service used by the lock screen. Optional
privileged actions use fixed-purpose helpers; Desktop Shell never accepts an
arbitrary root command from QML.

## External integrations

Desktop Shell deliberately uses the desktop's existing services instead of
maintaining a parallel state database:

| Integration | Purpose |
| --- | --- |
| Hyprland IPC and screencopy | workspaces, windows, focus, and switcher previews |
| Quickshell Networking | persistent NetworkManager Wi-Fi state and scanning |
| BlueZ and `bluetoothctl` | Bluetooth discovery, pairing, trust, and connections |
| PipeWire | global and per-stream playback/recording controls |
| UWSM | launching desktop entries outside the shell service cgroup |
| `cliphist` and Wayland clipboard tools | clipboard history and previews |
| `hyprpaper` | wallpaper application |
| MPRIS | media state and track-change notifications |
| systemd user services | lifecycle, status, and logs |

Applications are launched with `uwsm app --`. They must not become children of
the Quickshell process: restarting the shell must not terminate terminals,
browsers, or other applications it launched.

## State and runtime data

Persistent user state is kept below one `XDG_STATE_HOME/desktop-shell/` tree.
It contains launcher usage, focus and notification state, bounded telemetry,
clipboard previews, and the current wallpaper selection.

Transient browser-tab data and IPC sockets live below
`XDG_RUNTIME_DIR/desktop-shell/`. See [Browser tabs](browser-tabs.md) for the
data contract.

Search queries are not recorded. Launcher history stores desktop-entry IDs,
counts, and timestamps only. Invalid or absent state is treated as empty state
and rebuilt when necessary.

## Configuration flow

Nix options are evaluated before launch. Home Manager serializes the theme and
structured values such as workspaces, bar controls, and keybinding metadata to
one JSON file. The command backend validates that file and exposes resolved
values to QML through environment variables.

Runtime observations stay runtime-owned. Window lists, devices, PipeWire
nodes, network state, and output geometry are discovered from their source
services rather than copied into the Nix interface.
