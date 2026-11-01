# Contributing

The Nix flake packages the shell, command-line backend, and integration
modules together.

## Development environment

The standalone flake tracks NixOS unstable and the matching Home Manager branch
so development and CI use current Quickshell and Hyprland packages. System
integrations follow the consuming system’s inputs as described in
[Installation](docs/installation.md).

Enter the repository environment before running project tools:

```console
$ nix develop
```

Run the complete local check set before submitting a change:

```console
$ nix flake check
```

Build the default package when a change affects packaging or runtime inputs:

```console
$ nix build --quiet
```

The checks cover Nix, shell, QML, and the browser bridge. Test changes to
geometry, focus, and device controls in a nested or disposable Hyprland
session when practical. Include the result and any untested interactions in
the change description.

Run the relevant regressions inside `nix develop`:

| Change | Command |
| --- | --- |
| Network popup focus | `bash tests/native/network-popover-focus.sh` |
| Calendar navigation | `bash tests/native/calendar-navigation.sh` |
| Tray menus | `python3 tests/native/tray-menu.py` |
| Hyprland snapshots and sockets | `python3 tests/native/hyprland-client-snapshot.py` |
| Tailscale inbox | `bash tests/native/tailscale-model.sh` |
| Taildrop notifications | `bash tests/native/taildrop-notification.sh` |
| Taildrop saving | `python3 tests/native/taildrop-save.py` |

The network, calendar and tray tests require Wayland. For network focus changes,
also click the bar trigger repeatedly without moving the pointer. On Hyprland,
`python3 tests/native/tray-menu.py --pointer` tests stationary tray clicks;
it requires `wlrctl` and moves the cursor during the test.

## Source layout

- `src/` contains the Quickshell entry points, QML modules, and command backend.
- `browser-extension/` contains the Firefox-compatible extension and native
  messaging host.
- `nix/` contains the package and system integration modules.
- `docs/` contains user and developer documentation.
- `examples/home.nix` is the public NixOS + Hyprland Home Manager setup; keep it
  covered by the module checks when changing integration.

See [Architecture](docs/architecture.md) for the ownership boundaries between
these parts.

## Change guidelines

- Fix behavior at the owning layer. Keep presentation in QML, session and
  device operations in the backend, and deployment policy in Nix modules.
- Keep Hyprland-specific calls behind the shell's Hyprland integration rather
  than scattering new dispatch strings through unrelated components.
- Add a typed option only for durable user policy. Runtime observations and
  transient UI state do not belong in the module interface.
- Keep machine names, device identifiers, private paths, and application-specific
  exceptions out of defaults and examples.
- Declare every command used by the packaged backend as a runtime dependency.
- Preserve stable JSON shapes consumed by QML. If a contract must change,
  update the producer, consumer, tests, and documentation together.
- Add regression tests for command and parsing bugs. Keep fixtures focused on
  the affected command or component.
- Keep documentation practical. Document current behavior and supported
  configuration, not planned interfaces.

## Submitting changes

Keep commits focused enough to review independently. Include:

1. the behavior and ownership layer that changed;
2. automated checks that were run;
3. manual Hyprland testing, when the change affects interaction or rendering;
4. relevant hardware or compositor constraints.

By contributing, you agree that your contribution is licensed under the
[GNU General Public License v3.0 or later](LICENSE).
