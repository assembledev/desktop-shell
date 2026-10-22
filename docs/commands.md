# Commands

`desktop-shell` is the single public executable. It manages the user service,
opens shell surfaces, and provides the operations intended for Hyprland
keybindings.

Run `desktop-shell help` for the primary interface, `desktop-shell <command>
--help` or `desktop-shell help <command>` for a topic, and `desktop-shell
help-all` for all topics. Help works without a valid configuration or running
session.

The `audio`, `wifi`, `media`, `dnd`, `notifications`, and profile-state commands
return JSON through the running shell's native models. They require a running
shell built from the matching package and do not start or restart it. An absent
shell, missing command endpoint, or malformed IPC reply returns exit status 3.

## Lifecycle

| Command | Description |
| --- | --- |
| `desktop-shell start` | Start `desktop-shell.service` |
| `desktop-shell start --foreground` | Run Quickshell in the current terminal |
| `desktop-shell stop` | Stop the user service |
| `desktop-shell restart` | Restart the user service |
| `desktop-shell status` | Print the service state |
| `desktop-shell logs` | Show the last 200 service log lines |
| `desktop-shell logs --follow` | Follow service logs |
| `desktop-shell doctor` | Check configuration, commands, Hyprland, and service state |

`status` returns success only while the service is active; an inactive service
returns status `3`. `doctor` reports each check separately and returns non-zero
when a required command or the active Hyprland instance cannot be reached.
`restart` restarts only the shell user service; it never reboots the session or
machine.

`run` and `lock-run` are service implementation commands. Use
`start --foreground` for interactive debugging instead of calling `run`
directly.

## Shell surfaces

### Control center

```console
$ desktop-shell toggle
$ desktop-shell open
$ desktop-shell close
$ desktop-shell wifi-page
$ desktop-shell bluetooth-page
$ desktop-shell display-page
$ desktop-shell audio-page
```

The first invocation starts the user service when necessary. `wifi-page` and
`bluetooth-page` open the control center directly on the corresponding page;
`display-page` opens the connected-output and layout controls; `audio-page`
opens output/input devices and application audio streams.

The control center is attached beneath the bar. Quick controls stay above an
independently scrolling notification history. Sound opens the detailed audio
page. Lock and power actions belong to the separate power menu.

On NixOS, the main page footer shows the running system's local-store
registration time and `switch` or `test`. `switch` means the running closure
matches a retained system generation or one of its specialisations; `test`
means it does not. This is inferred state, not a record of the last rebuild
command: testing an already retained generation also displays `switch`.
The timestamp can reflect an import rather than build completion or activation.
The read-only `desktop-shell system status-json` query uses the host's Nix CLI;
when its local-store metadata API is unavailable, the date is unavailable.
The footer refreshes on opening and while the main page is visible. It creates
no rebuild history and does not require changes to rebuild commands.

The display page provides a centered, draggable output arrangement. Dragging
chooses exact top/center/bottom placements beside another display, or
left/center/right placements above or below it. The shared edges stay touching;
placements that overlap another display are skipped.
Geometry uses scaled, rotated dimensions. Overlapping layouts
are rejected before application. Extend, Duplicate, Internal only, and External
only presets are available alongside per-output mode and scale controls. Testing a change starts a 20-second confirmation deadline
backed by a transient systemd user timer and visibly locks further editing. A
confirmed layout is saved for the same set of physical displays and restored
when that set reconnects. **Reset layout** removes the saved profile for the connected display
set before reloading Hyprland's declarative monitor rules.

### Network

Click the network icon between the keyboard language and notification bell to
open details on that output. It shows the active Wi-Fi or Ethernet uplink;
Wi-Fi has four signal levels. The connection header opens the existing Wi-Fi
selection page. Addresses, gateways and link DNS values copy when clicked;
confirmation appears inline beside the value, without a reserved footer.
Global IPv6 addresses appear when assigned. Escape or clicking outside closes
the popover.

Local details come from NetworkManager and the physical interface. Link rate
is distinct from the current receive/send traffic rate. Ping targets `1.1.1.1`
and follows normal system routing, including VPNs. Details, traffic and ping
refresh every two seconds while the popover is open; closing it stops probes
and clears the traffic baseline. A timed-out or unavailable ping does not imply
that Wi-Fi or Ethernet is disconnected. Missing data is shown as unavailable.
Public IPv4 is queried over HTTPS from `https://ip.me` on opening and every
30 seconds while open, through normal routing including VPNs. This service
sees the current public/VPN egress IP. The address is copyable and cleared on
closing. Transient request failures are retried once within a ten-second
process deadline. A failed lookup is labelled separately from a disconnected
link; `status-json` includes its error category (DNS, connection, TLS, service,
timeout or invalid response). No speed test runs.

```console
$ desktop-shell network open
$ desktop-shell network close
$ desktop-shell network toggle
$ desktop-shell network status-json
```

`status-json` reads the shared model without starting probes or the service.
Connection details are cached and may be absent until the popover is opened.
The bar's physical-uplink identity also refreshes when native device state
changes and every ten seconds. Networking requires a running NetworkManager;
the package supplies the read-only command-line tools used for details.

### Launcher

```console
$ desktop-shell launcher toggle
$ desktop-shell launcher open
$ desktop-shell launcher focus
$ desktop-shell launcher close
```

`focus` opens the launcher in existing-window and browser-tab mode. Application
launches and usage history stay inside the shell's native model rather than
round-tripping through the CLI backend.

Configured profiles are available as `@<name>` launcher results. Applying one
launches missing applications directly on their declared workspaces with native
silent placement and no initial focus, then moves existing matching windows
there without following them. Later application activation requests remain
enabled.

```console
$ desktop-shell profile list-json
$ desktop-shell profile apply <name>
$ desktop-shell profile status-json <name>
$ desktop-shell profile apply <name> --wait
```

`apply` without `--wait` preserves asynchronous dispatch. `status-json` requests
a fresh compositor snapshot and reports `open`, `placed`, `total`, `converged`,
`entriesReady`, `applying`, `queued`, and `lastResult`. The last result describes
the controller's dispatch, not completion of newly launched applications.

`apply --wait` uses a 30-second verification budget and succeeds only after all
configured applications have matching windows on their declared workspaces,
with no pending apply for that profile. Missing windows, application startup
failure, or placement that does not converge produce a nonzero exit status.
Timing out does not cancel application launches or undo window moves.

### Window switcher

```console
$ desktop-shell alttab next
$ desktop-shell alttab prev
$ desktop-shell alttab commit
$ desktop-shell alttab cancel
$ desktop-shell direction l
$ desktop-shell direction r
$ desktop-shell direction u
$ desktop-shell direction d
```

Bind `next` and `prev` to Alt-Tab presses and `commit` to Alt release. A
direction command moves the switcher selection while the overview is open and
otherwise asks Hyprland to focus in that direction.

### Other surfaces

| Command | Description |
| --- | --- |
| `desktop-shell cheatsheet toggle` | Toggle the keybinding reference |
| `desktop-shell pick` | Open the wallpaper picker |
| `desktop-shell lock` | Start or refocus the lock screen; wait for compositor confirmation, failing if unconfirmed within 10 seconds after startup |
| `desktop-shell lock status` | Print `true` only when the compositor has confirmed the session lock, otherwise `false` |
| `desktop-shell clipboard open` | Open clipboard history |
| `desktop-shell clipboard close` | Close clipboard history |
| `desktop-shell clipboard toggle` | Toggle clipboard history |
| `desktop-shell focus on` | Hide the bar and persist focus mode |
| `desktop-shell focus off` | Leave focus mode and show the bar |
| `desktop-shell bar show` | Reveal the bar |
| `desktop-shell bar hide` | Conceal the bar |

## Audio, Wi-Fi, media and notifications

### Audio

```console
$ desktop-shell audio status-json
$ desktop-shell audio devices-json
$ desktop-shell audio streams-json
$ desktop-shell audio volume 35
$ desktop-shell audio mute on input
$ desktop-shell audio volume 60 <node-name-or-id>
$ desktop-shell audio default output <node-name-or-id>
```

The target defaults to `output`; `input` selects the default microphone. Exact
node names and current PipeWire node IDs address other devices or application
streams. IDs are session-local and names may change after device replacement;
query the current nodes before targeting one. Missing or ambiguous targets fail.

Volume uses percentages from 0 to 150 and preserves mute. `audio mute` accepts
`on`, `off`, or `toggle`. Default-device selection accepts `output` or `input`
and only a hardware/device node of that direction. It changes the PipeWire
preference; it does not promise to reroute every existing application stream.

Queries return defaults, devices and streams, including names, IDs, readiness,
volume and mute. All-node inspection keeps the native tracker active for five
seconds after the last request. Writes are issued once and succeed only after
the requested state is observed, with a three-second observation budget after
initial node synchronization. Success returns `{applied:true,node:...}`. A
failure/timeout does not undo a request that may still take effect.

### Wi-Fi

```console
$ desktop-shell wifi status-json
$ desktop-shell wifi networks-json
$ desktop-shell wifi scan
$ desktop-shell wifi on
$ desktop-shell wifi connect "Saved network"
$ desktop-shell wifi disconnect "Saved network"
```

These commands use the control center's NetworkManager adapter and network
model. `status-json` includes availability, hardware block, radio state, current
SSID, signal, busy/scanning state and cached networks. Signals are percentages.
`networks-json` returns the cached network list without starting a scan.

`scan` enables discovery for 15 seconds, then releases it unless the Wi-Fi page
still needs scanning. `connect` accepts a unique visible saved SSID; authenticate
new networks through `wifi-page`. No password is accepted on the command line.
`off` disables Wi-Fi and may disconnect this machine.

Actions return `{accepted:true,...}` for the request. Connection, radio and
scan completion are asynchronous; inspect `status-json` for the resulting state.
A disabled, blocked, busy or unavailable adapter produces a clear error.

### Media

```console
$ desktop-shell media status-json
$ desktop-shell media players-json
$ desktop-shell media pause
$ desktop-shell media next org.mpris.MediaPlayer2.example
```

Controls are `play`, `pause`, `toggle`, `stop`, `next`, and `previous`. The
optional player is its exact MPRIS D-Bus name; omission selects the same active
player as the shell. Queries expose track metadata, playback, position/length
in seconds when supported, and supported controls. Unsupported actions fail.
Actions acknowledge the request with `{accepted:true,...}`; query playback
state separately to observe completion.

### DND and notification history

```console
$ desktop-shell dnd status-json
$ desktop-shell dnd on
$ desktop-shell dnd off
$ desktop-shell dnd toggle
$ desktop-shell notifications status-json
$ desktop-shell notifications list-json
$ desktop-shell notifications dismiss <id>
$ desktop-shell notifications clear
```

DND commands share the UI's persisted preference and return `{dnd,count}`.
Notification text is returned only by explicit `list-json`, with IDs, application,
summary, body and capture time in epoch milliseconds. History excludes transient
notifications. `dismiss` addresses a current ID and fails when it no longer
exists. `clear` uses the UI's existing undo window and final-dismiss behavior.

## Volume shortcuts and brightness

The volume commands operate on the default PipeWire output through `pamixer`:

```console
$ desktop-shell volume up
$ desktop-shell volume down
$ desktop-shell volume mute
```

Brightness uses a kernel backlight when one is usable, then DDC/CI when a
writable monitor is detected:

```console
$ desktop-shell brightness capabilities-json
$ desktop-shell brightness get
$ desktop-shell brightness set 65
$ desktop-shell brightness up
$ desktop-shell brightness down
```

For DDC/CI, `capabilities-json` includes `valuePath`, the atomically updated
brightness cache. `get` initializes it; brightness writes update it. The UI
watches this file for changes instead of polling it. Kernel backlights use
udev change events.

`idle-dim` and `idle-restore` are intended for an idle daemon. Restore returns
to the exact value captured by the preceding dim operation.

## Wallpaper operations

The picker calls these commands internally; they are also useful in scripts:

| Command | Description |
| --- | --- |
| `desktop-shell list-json` | List images in the configured wallpaper directory |
| `desktop-shell current` | Print the selected wallpaper path |
| `desktop-shell set <path>` | Select and apply an image |
| `desktop-shell apply` | Reapply the selected image |
| `desktop-shell preview <path>` | Apply a transient picker preview |

The picker lists files below the configured wallpaper directory. `set` also
accepts an explicit image path, which is useful for external wallpaper tools.

## Configuration and IPC

```console
$ desktop-shell config path
$ desktop-shell config show
$ desktop-shell ipc list
$ desktop-shell ipc call <target> <method> [arguments...]
```

`config show` prints the fully generated JSON consumed by the running shell.
The IPC commands are a debugging interface to Quickshell and may change when a
QML surface is refactored; use the named shell commands in keybindings and
scripts.

## Configured network controls

Bar network controls are trusted configuration records with a stable ID. QML
uses:

```console
$ desktop-shell network-control status <id>
$ desktop-shell network-control toggle <id>
```

Each command executes the corresponding argv array from the generated
configuration. Desktop Shell does not grant privileges to provider commands;
the surrounding NixOS configuration must supply any narrowly scoped helper it
requires.

## Browser bridge

```console
$ desktop-shell browser-tabs state-path
```

This prints the runtime snapshot path. `browser-tabs activate ...` is an
internal launcher-to-extension protocol. See [Browser tabs](browser-tabs.md)
for installation and privacy details.

## Exit status

Unknown public commands and invalid public arguments return `2` and print
usage. Native-model command errors return `1`; unavailable or incompatible
shell IPC returns `3`. Successful JSON writes explicitly distinguish observed
`applied` state from asynchronously `accepted` requests. Backend inspection and device commands return the underlying failure
status unless their contract explicitly treats an unavailable optional service
as empty state.
