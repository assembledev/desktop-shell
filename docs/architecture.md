# Architecture

Desktop Shell combines Quickshell surfaces, a command backend, and Nix modules.
The package builds them from one source tree and passes generated configuration
to the runtime. Hyprland is the compositor integration.

## Processes and lifecycle

`desktop-shell.service` runs `desktop-shell run`, which starts `src/shell.qml`.
That process owns bars, the launcher and switcher, the control center and
notification server, clipboard and wallpaper pickers, and media notifications.
Its systemd lifetime follows the configured graphical-session target.

The PAM lock runs separately from `src/lock.qml`. The optional greetd greeter
starts `src/greeter.qml` under Cage. Both use the shared `LockView.qml`
presentation with their own authentication and lifecycle. Restarting the
ordinary shell leaves the lock process independent. See
[Session lock](lock-security.md) and [Login greeter](greeter.md).

Applications launch through `uwsm app --` into separate user units. They must
outlive a shell restart.

## Code owners

| Area | Owner |
| --- | --- |
| Entry points | `src/shell.qml`, `src/lock.qml`, `src/greeter.qml` |
| UI and interaction | `src/modules/` |
| CLI routing | `src/backend/desktop-shell.sh` |
| Device, session, and file operations | `src/backend/lib/` |
| Compositor helpers | `src/hyprland/` |
| Package and runtime dependencies | `nix/package.nix` |
| User configuration and services | `nix/home-manager-module.nix` |
| System PAM and greeter | `nix/nixos-module.nix` |
| Browser bridge | `browser-extension/`, `nix/browser-tab-bridge.nix` |

Keep presentation and interaction state in QML. Use the backend for device
commands, file operations, environment discovery, and validated display
transactions. Nix modules own durable policy, packages, and service setup.
Runtime observations such as windows, devices, audio nodes, and output geometry
come from their live services.

## Hyprland

`HyprlandAdapter.qml` centralizes compositor operations. Authoritative
`j/clients` snapshots from Hyprland's request socket supply window identity and
geometry; Quickshell's persistent model supplies change events. Launcher
indexes refresh when applications or clients change, so typing only filters
and ranks the current index.

`ProfileController.qml` launches and places profile applications. It serializes
moves using compositor events and uses standard desktop-entry metadata for
window identity. The CLI's profile inspection takes a separate snapshot;
launch acceptance and verified placement are distinct results.

`src/hyprland/init.lua` loads blur rules for shell layers, contextual popup
Escape handling, and the `desktopShell.windowPopout` API. Home Manager installs
and loads this entry point for Lua configuration; externally managed Hyprland
loads the same file. Consumers own application bindings, monitor rules,
workspace placement, and layout policy. See [Keybindings](keybindings.md).

## Shared models and displays

`src/shell.qml` creates a bar for each selected output around one shared
`BarState.qml`. Telemetry, battery warnings, network controls, keyboard state,
and command endpoints have one owner rather than one per bar. The control
center owns one notification server and shared event models.

`ScreenPlacement.qml` captures the output when a surface opens and invalidates
it when that output disappears. `BarOverlayWindow.qml` owns popover geometry
and input focus: pointer opens keep the bar trigger reachable; keyboard opens
request keyboard focus. Per-output views present their assigned notifications
and OSD items without duplicating models or polling.

Display changes are one validated transaction through Hyprland's Lua monitor
API. Before applying, the backend records the previous layout in the runtime
directory and arms a transient systemd timer. Confirmation cancels the timer
and saves the layout for the physical-output set; expiry or rejection restores
the previous layout. Restoring startup rules removes the saved profile for that
set and reloads Hyprland.

## Desktop services and commands

The shell reads PipeWire, NetworkManager, BlueZ, MPRIS, and Hyprland rather than
keeping a parallel desktop state database. hyprpaper applies wallpapers;
cliphist stores clipboard content. Optional Tailscale controls use LocalAPI for
status and peers and the CLI for supported actions.

`lib/commands.sh` exposes semantic JSON endpoints through the existing QML
owners for audio, Wi-Fi, media, notifications, and profiles. Reads do not open
panels or start the service. Producers, consumers, tests, and documentation
share these contracts; change them together.

Network providers use one of three complete contracts: built-in Tailscale,
a system unit with explicit action commands, or a custom status/toggle argv
pair. The backend validates and interprets providers. The host owns daemon
setup, operator rights, secrets, and privileged helpers. See
[Network controls](configuration.md#network-controls).

## Configuration and packaging

Home Manager serializes typed options into one JSON file. The backend resolves
that file through `lib/config-environment.jq` and passes values as NUL-delimited
data, without evaluating shell code. Add configuration projections there rather
than starting a parser for each field.

`nix/package.nix` assembles the QML tree, backend, defaults, and Lua files. Its
wrapper supplies runtime commands and immutable source paths. Backend commands
must be packaged dependencies rather than assumptions about the interactive
shell's PATH.

The Home Manager module owns the shell service, clipboard watchers, optional
pairing agent, generated configuration, and state directories. The NixOS module
supplies PAM and the optional greeter. Neither module owns the user's full
compositor configuration or desktop service policy.

## State

Persistent state lives below `$XDG_STATE_HOME/desktop-shell/`: preferences,
launcher usage, telemetry, clipboard previews and capture ages, wallpaper
selection, and confirmed display profiles. Search queries are not recorded;
launcher history stores desktop-entry IDs, counts, and timestamps. Invalid or
missing state is treated as empty where it can be rebuilt.

Clipboard watchers store content through cliphist and atomically update capture
ages. The age file retains record identities so a reused ID cannot inherit an
old timestamp. Entries captured elsewhere have unknown ages.

Transient IPC, browser-tab snapshots, and display rollback data live below
`$XDG_RUNTIME_DIR/desktop-shell/`. The browser bridge's permissions, lifetime,
and published fields are documented in [Browser tabs](browser-tabs.md).

## Shared visual contracts

[Design notes](../DESIGN.md) describes theme roles and their owners. Reuse shared
controls, `ShellSymbol`, and common input-intent handling. Audio presentations
share `AudioStatus.js`; output/input models remain native PipeWire objects.
Component geometry belongs to the component; bar spacing belongs to
`BarSpacing.qml`, and animation roles belong to `Motion.qml`.
