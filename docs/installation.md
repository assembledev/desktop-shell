# Installation

The supported setup is an existing **NixOS + Hyprland** desktop, with Home
Manager managing user configuration and UWSM managing the Wayland session.
Start from a working [Lua configuration](https://wiki.hypr.land/configuring/core/).
Convert existing Hyprlang settings and bindings before importing the example;
`configType` selects the output syntax rather than translating those settings.
The flake provides packages for `x86_64-linux` and `aarch64-linux`.

## Add the flake and modules

Add Desktop Shell to your system flake. Keep the Nixpkgs and Home Manager
inputs already used by your system:

```nix
inputs.desktop-shell = {
  url = "github:assembledev/desktop-shell";
  inputs.nixpkgs.follows = "nixpkgs";
  inputs.home-manager.follows = "home-manager";
};
```

Import the NixOS module for lock-screen PAM authentication and the Home Manager
module for the package, configuration, and user services. In your existing
`nixosSystem` module list:

```nix
modules = [
  ./configuration.nix
  desktop-shell.nixosModules.default
  home-manager.nixosModules.home-manager
  {
    programs.desktop-shell.enable = true;

    home-manager.sharedModules = [
      desktop-shell.homeManagerModules.default
    ];
    home-manager.users.your-user.imports = [
      "${desktop-shell}/examples/home.nix"
    ];
  }
];
```

Here `desktop-shell` and `home-manager` are inputs passed to your flake's
`outputs` function. Replace `your-user` with your account. If Home Manager is
already imported, add the shared module and user import to that configuration.
Keep your existing `home.stateVersion`.

The [example](../examples/home.nix) enables the shell, loads its Hyprland Lua
integration, starts hyprpaper, and supplies starter shell keybindings with
matching cheat-sheet entries. It leaves applications, workspace bindings,
layouts, and monitor rules to your Hyprland configuration. Review its shortcuts for conflicts before
importing it.

For a smaller setup, import only `desktop-shell.homeManagerModules.default`,
set `programs.desktop-shell.enable = true` in your user configuration, and add
[the bindings you want](keybindings.md).

## Session and system services

Enable Hyprland with UWSM on the NixOS side:

```nix
programs.hyprland = {
  enable = true;
  withUWSM = true;
};
```

With UWSM, disable Home Manager's separate Hyprland systemd integration. The
example already sets this:

```nix
wayland.windowManager.hyprland.systemd.enable = false;
```

At login, select **Hyprland (uwsm-managed)** in your display manager. From a
text login, run `uwsm start hyprland.desktop`. See the
[NixOS Wiki](https://wiki.nixos.org/wiki/Hyprland) and
[Hyprland UWSM guide](https://wiki.hypr.land/useful-utilities/uwsm/) for session
setup.

The shell uses existing desktop services. Enable the ones you need in the
surrounding system:

| Feature | System service |
| --- | --- |
| Wi-Fi and network details | `networking.networkmanager.enable = true` |
| Audio | PipeWire with WirePlumber; see [PipeWire](https://wiki.nixos.org/wiki/PipeWire) |
| Bluetooth | `hardware.bluetooth.enable = true` |
| Wallpaper | hyprpaper; enabled by the example |
| File choosers, including Taildrop save | A configured desktop portal with a file chooser backend |

Keep one owner for clipboard capture, Bluetooth pairing, the bar, and desktop
notifications. The module starts its own clipboard watchers and Blueman pairing
agent. Disable the corresponding shell option when another component already
owns that task; see [Configuration](configuration.md#module-options).

The package supplies Quickshell and backend command dependencies. The module
installs its default fonts. For external-monitor brightness, enable DDC/CI in
the monitor and configure user access to its I2C device; see
[DDC/CI](https://wiki.nixos.org/wiki/Backlight#External_Monitors). A kernel
backlight uses brightnessctl instead.

## First login

Rebuild your existing NixOS configuration, then log into the UWSM session.
Run:

```console
$ desktop-shell status
$ desktop-shell doctor
$ desktop-shell launcher open
```

The service starts with `graphical-session.target`. If the session was already
running during activation, use `desktop-shell start`. Remove any old
`exec-once` or autostart command that starts another copy of the shell.

Try launching an application, opening the control center, and locking and
unlocking the session. Continue with the [user guide](user-guide.md), or use
[Troubleshooting](troubleshooting.md) if a check fails.

Set your [wallpaper directory](configuration.md#wallpaper),
[keyboard layout labels](configuration.md#keyboard-layout-labels), and
[workspace topology](configuration.md#workspaces) to match your setup.

## Hyprland integration

When Home Manager manages Hyprland, use Lua configuration:

```nix
wayland.windowManager.hyprland = {
  enable = true;
  configType = "lua";
};
```

The module loads `$XDG_CONFIG_HOME/desktop-shell/hyprland/init.lua` automatically.
That file configures blur for shell layers, popup Escape handling, and the
window pop-out API. Application bindings and monitor policy stay in your
configuration.

For a Hyprland configuration managed outside Home Manager, load that same file
once from your Lua configuration:

```lua
local configHome = os.getenv("XDG_CONFIG_HOME")
if not configHome or configHome == "" then
  configHome = os.getenv("HOME") .. "/.config"
end
desktopShell = dofile(configHome .. "/desktop-shell/hyprland/init.lua")
```

If your compositor is pinned or patched, set
`programs.desktop-shell.hyprlandPackage` to the same package so the backend uses
its matching `hyprctl`.

## Optional integrations

- [Login greeter](greeter.md) — replace your login manager with the greetd view.
- [Browser tabs](browser-tabs.md#installation) — add Firefox-compatible tab search.
- [Network providers](configuration.md#network-controls) — add Tailscale or a VPN
  control to the bar.
- [Session lock](lock-security.md#system-integration) — configure automatic and
  pre-suspend locking through Hypridle.

## Try a checkout

Print help without installing a module:

```console
$ nix run . -- help
```

Inside an existing Hyprland session, run a foreground instance:

```console
$ nix run . -- start --foreground
```

Stop an installed `desktop-shell.service` first to avoid a duplicate instance.
This reads your installed Desktop Shell configuration when present, falling
back to built-in defaults otherwise. System PAM, session, and service
prerequisites still apply.

## Flake outputs

| Output | Purpose |
| --- | --- |
| `packages.<system>.default` / `.desktop-shell` | Shell package |
| `packages.<system>.browser-native-host` | Mozilla native messaging host |
| `packages.<system>.browser-extension-unsigned` | Development XPI |
| `apps.<system>.default` | `desktop-shell` command |
| `homeManagerModules.default` | User configuration and services |
| `nixosModules.default` | PAM authentication and optional greetd greeter |
| `checks.<system>.*` | Package, module, and source checks |
| `devShells.<system>.default` | Contributor tools |
| `formatter.<system>` | Nix formatter |
