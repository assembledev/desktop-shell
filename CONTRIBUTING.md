# Contributing

Desktop Shell is developed as one Nix flake. Shell sources, the command-line
backend, packaging, and modules should continue to work as one coherent unit.

## Development environment

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
$ nix build
```

The check set covers Nix, shell, QML, and the browser bridge. A successful
evaluation alone does not prove that layer-shell geometry, focus handling, or
hardware-backed controls behave correctly. Test affected interactions in a
nested or disposable Hyprland session when practical, and describe the manual
test in the change.

## Source layout

- `src/` contains the Quickshell entry points, QML modules, and command backend.
- `browser-extension/` contains the Firefox-compatible extension and native
  messaging host.
- `nix/` contains the package and system integration modules.
- `docs/` contains user and developer documentation.

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
- Prefer a narrow deterministic regression test when a bug exposes a fragile
  command or parsing contract. Do not build a parallel mock desktop stack.
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
