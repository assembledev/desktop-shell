# Installation

Desktop Shell is distributed as a Nix flake. The examples use a checkout next
to the system configuration; replace the `path:` URL with the repository's
remote flake URL when appropriate.

## Flake input

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    desktop-shell = {
      url = "path:../desktop-shell";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
  };
}
```

The flake exports packages and modules for `x86_64-linux` and `aarch64-linux`.

## NixOS with Home Manager

Import both modules. The NixOS module creates the PAM service used by the lock;
the Home Manager module installs and starts the user shell.

```nix
{
  outputs =
    inputs@{
      nixpkgs,
      home-manager,
      desktop-shell,
      ...
    }:
    {
      nixosConfigurations.workstation = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          desktop-shell.nixosModules.default
          home-manager.nixosModules.home-manager

          ({ pkgs, ... }: {
            # NixOS-side PAM integration.
            programs.desktop-shell.enable = true;

            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              sharedModules = [ desktop-shell.homeManagerModules.default ];

              users.user = { pkgs, ... }: {
                home.stateVersion = "26.05";

                programs.desktop-shell = {
                  enable = true;
                  package = desktop-shell.packages.${pkgs.stdenv.hostPlatform.system}.default;
                };
              };
            };
          })
        ];
      };
    };
}
```

Replace `user` and the state version with those already owned by the system
configuration. `programs.desktop-shell.lock.enable` defaults to `true` on the
NixOS side. Set it to `false` only when the lock screen is disabled or the PAM
service is created elsewhere.

## Standalone Home Manager

Import the Home Manager module directly:

```nix
{ inputs, pkgs, ... }:
{
  imports = [ inputs.desktop-shell.homeManagerModules.default ];

  programs.desktop-shell = {
    enable = true;
    package =
      inputs.desktop-shell.packages.${pkgs.stdenv.hostPlatform.system}.default;
  };
}
```

The shell and all surfaces except authentication can run with Home Manager
alone. `desktop-shell lock` requires a system PAM service named
`desktop-shell-lock`; importing `nixosModules.default` is the supported NixOS
way to provide it.

## System prerequisites

The modules do not take ownership of the complete desktop stack. Configure
these services in the surrounding system:

- Hyprland and a UWSM-managed Wayland session;
- systemd user sessions;
- NetworkManager for Wi-Fi controls;
- PipeWire for global and per-stream audio controls;
- BlueZ for Bluetooth controls;
- a running `hyprpaper` instance for wallpaper changes.

The shell package supplies Quickshell and its command dependencies. The Home
Manager module installs the default Fira Code Nerd Font. When overriding
`theme.fontFamily`, add the selected family to the user profile as well.

For DDC/CI brightness, enable I2C device access and DDC/CI in the monitor's
on-screen settings. Systems with a kernel backlight do not need DDC/CI.

## Hyprland layer rules

Desktop Shell uses translucent layer surfaces. Add blur rules in the Hyprland
Lua configuration for the intended appearance:

```lua
local desktopShellBlurLayers = {
  "quickshell:bar",
  "quickshell:batteryAnalysis",
  "quickshell:calendar",
  "quickshell:trayShelf",
  "quickshell:powerMenu",
  "quickshell:launcher",
  "quickshell:controlCenter",
  "quickshell:controlCenterOsd",
  "quickshell:notificationPopups",
  "quickshell:nowPlaying",
  "quickshell:clipboardHistory",
  "quickshell:cheatsheet",
  "quickshell:windowSwitcher",
}

for _, namespace in ipairs(desktopShellBlurLayers) do
  hl.layer_rule({
    match = { namespace = namespace },
    blur = true,
    ignore_alpha = 0.5,
  })
end
```

The namespaces are stable integration points. Use `hyprctl layers` to inspect
the surfaces currently mapped and the
[Hyprland layer-rule reference](https://wiki.hypr.land/Configuring/Basics/Window-Rules/)
for compositor-version details.

## First activation

Rebuild the owning NixOS or Home Manager configuration, then inspect the user
service:

```console
$ desktop-shell status
$ desktop-shell doctor
$ desktop-shell logs
```

If the graphical target was already active but the service has not started:

```console
$ desktop-shell start
```

Connect commands to the compositor using [Keybindings](keybindings.md). The
module intentionally leaves existing Hyprland binding policy unchanged.

## Try from a checkout

The default app can print help without installing the module:

```console
$ nix run . -- help
```

From an active Hyprland session, run an isolated foreground instance with:

```console
$ nix run . -- start --foreground
```

Stop any installed `desktop-shell.service` first to avoid duplicate Quickshell
instances.

## Browser-tab integration

The flake exposes the two browser-side artifacts separately:

```console
$ nix build .#browser-native-host
$ nix build .#browser-extension-unsigned
```

Pass the native host to the Nix browser package so its wrapper registers the
manifest:

```nix
{ inputs, pkgs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
in
{
  programs.firefox.package = pkgs.firefox.override {
    nativeMessagingHosts = [
      inputs.desktop-shell.packages.${system}.browser-native-host
    ];
  };

  programs.desktop-shell.browserTabs.enable = true;
}
```

`browser-extension-unsigned` is a development XPI. Normal Firefox release
profiles require a signed extension; sign or package the artifact through the
browser's supported deployment channel, then install it in the same browser
that receives the native host. See [Browser tabs](browser-tabs.md) for the data
contract and diagnostics.

## Flake outputs

| Output | Purpose |
| --- | --- |
| `packages.<system>.default` | Desktop Shell package |
| `packages.<system>.desktop-shell` | Named alias for the default package |
| `packages.<system>.browser-native-host` | Mozilla native messaging manifest and host |
| `packages.<system>.browser-extension-unsigned` | Development XPI |
| `apps.<system>.default` | `desktop-shell` command |
| `homeManagerModules.default` | Home Manager integration |
| `nixosModules.default` | PAM lock integration |
| `checks.<system>.*` | package, module, source, and bridge checks |
| `devShells.<system>.default` | contributor toolchain |
| `formatter.<system>` | Nix tree formatter |
