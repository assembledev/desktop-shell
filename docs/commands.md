# Commands

`desktop-shell` is the single public executable. It manages the user service,
opens shell surfaces, and provides the operations intended for Hyprland
keybindings.

Run `desktop-shell help` for the primary interface and
`desktop-shell help-all` for integration commands.

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
```

The first invocation starts the user service when necessary. `wifi-page` and
`bluetooth-page` open the control center directly on the corresponding page;
`display-page` opens the connected-output and layout controls.

The display page provides a draggable output arrangement together with Extend,
Duplicate, Internal only, and External only presets and per-output mode and
scale controls. Testing a change starts a 20-second confirmation deadline
backed by a transient systemd user timer and visibly locks further editing. A
confirmed layout is saved for the same set of physical displays and restored
when that set reconnects. The page shows the configured startup rules and
**Restore startup layout** removes the saved profile for the connected display
set before reloading Hyprland's declarative monitor rules.

### Launcher

```console
$ desktop-shell launcher toggle
$ desktop-shell launcher open
$ desktop-shell launcher focus
$ desktop-shell launcher close
```

`focus` opens the launcher in existing-window and browser-tab mode. The
backend-only forms `launcher launch <desktop-entry-id>` and `launcher history`
are used by the QML model.

Configured profiles are available as `@<name>` launcher results. Applying one
launches missing applications directly on their declared workspaces with native
silent placement and per-exec activation focus disabled, then moves existing
matching windows there without following them.

```console
$ desktop-shell profile list-json
$ desktop-shell profile apply <name>
```

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
| `desktop-shell lock` | Start or refocus the lock screen |
| `desktop-shell lock status` | Print `true` or `false` |
| `desktop-shell clipboard open` | Open clipboard history |
| `desktop-shell clipboard close` | Close clipboard history |
| `desktop-shell clipboard toggle` | Toggle clipboard history |
| `desktop-shell focus on` | Hide the bar and persist focus mode |
| `desktop-shell focus off` | Leave focus mode and show the bar |
| `desktop-shell bar show` | Reveal the bar |
| `desktop-shell bar hide` | Conceal the bar |

## Audio and brightness

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
usage. Backend inspection and device commands return the underlying failure
status unless their contract explicitly treats an unavailable optional service
as empty state.
