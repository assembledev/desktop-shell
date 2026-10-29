{
  description = "A keyboard-first Quickshell desktop shell for Hyprland";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      packageFor =
        system:
        import ./nix/package.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          source = ./.;
        };
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          desktopShell = packageFor system;
          browserTabBridge = import ./nix/browser-tab-bridge.nix {
            inherit pkgs;
            source = ./.;
          };
        in
        {
          default = desktopShell;
          desktop-shell = desktopShell;
          browser-native-host = browserTabBridge.nativeMessagingHost;
          browser-extension-unsigned = browserTabBridge.unsignedExtension;
        }
      );

      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/desktop-shell";
          meta.description = "Run the Desktop Shell command-line interface";
        };
      });

      homeManagerModules.default = import ./nix/home-manager-module.nix;
      nixosModules.default = import ./nix/nixos-module.nix;

      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          desktopShell = packageFor system;
          browserTabBridge = import ./nix/browser-tab-bridge.nix {
            inherit pkgs;
            source = ./.;
          };
          homeConfiguration = home-manager.lib.homeManagerConfiguration {
            inherit pkgs;
            modules = [
              self.homeManagerModules.default
              {
                home = {
                  username = "desktop-shell-test";
                  homeDirectory = "/home/desktop-shell-test";
                  stateVersion = "25.11";
                };
                programs.desktop-shell = {
                  enable = true;
                  package = desktopShell;
                  bluetooth.agent.enable = false;
                  launcher = {
                    profiles.check-profile = {
                      label = "Check profile";
                      icon = "applications-other";
                      applications = [
                        {
                          id = "org.example.Demo.desktop";
                          workspace = 1;
                        }
                      ];
                    };
                    autoStartProfile = "check-profile";
                  };
                };
              }
            ];
          };
          hyprlandHomeConfiguration = homeConfiguration.extendModules {
            modules = [
              {
                wayland.windowManager.hyprland = {
                  enable = true;
                  configType = "lua";
                  package = null;
                  portalPackage = null;
                  systemd.enable = false;
                };
              }
            ];
          };
          tailscaleHomeConfiguration = hyprlandHomeConfiguration.extendModules {
            modules = [
              {
                programs.desktop-shell.bar.networkControls = [
                  {
                    id = "tailscale";
                    label = "Tail";
                  }
                ];
              }
            ];
          };
          exampleHomeConfiguration = home-manager.lib.homeManagerConfiguration {
            inherit pkgs;
            modules = [
              self.homeManagerModules.default
              ./examples/home.nix
              {
                home = {
                  username = "desktop-shell-example";
                  homeDirectory = "/home/desktop-shell-example";
                  stateVersion = "26.05";
                };
                xdg.stateHome = "/home/desktop-shell-example/.state";
                programs.desktop-shell.wallpaper.default = pkgs.writeText "wallpaper.svg" ''
                  <svg xmlns="http://www.w3.org/2000/svg" width="1" height="1"/>
                '';
              }
            ];
          };
          nixosConfiguration = nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              self.nixosModules.default
              {
                system.stateVersion = "25.11";
                users.users.desktop-shell-test.isNormalUser = true;
                programs.desktop-shell = {
                  enable = true;
                  package = desktopShell;
                  greeter = {
                    enable = true;
                    user = "desktop-shell-test";
                    wallpaperPath = "/var/lib/desktop-shell-greeter/wallpaper";
                  };
                };
              }
            ];
          };
        in
        {
          package = desktopShell;
          home-manager =
            assert homeConfiguration.config.programs.desktop-shell.bar.networkControls == [ ];
            assert
              !(builtins.elem (toString pkgs.tailscale) (map toString homeConfiguration.config.home.packages));
            assert
              !(builtins.elem (toString pkgs.tailscale) (
                map toString hyprlandHomeConfiguration.config.home.packages
              ));
            assert builtins.elem (toString pkgs.tailscale) (
              map toString tailscaleHomeConfiguration.config.home.packages
            );
            assert nixpkgs.lib.hasInfix "desktopShell = dofile"
              hyprlandHomeConfiguration.config.wayland.windowManager.hyprland.extraConfig;
            assert hyprlandHomeConfiguration.config.wayland.windowManager.hyprland.package == null;
            assert !hyprlandHomeConfiguration.config.wayland.windowManager.hyprland.systemd.enable;
            assert
              (toString homeConfiguration.config.xdg.configFile."desktop-shell/hyprland".source)
              == "${desktopShell}/share/desktop-shell/hyprland";
            assert builtins.elem "graphical-session.target"
              homeConfiguration.config.systemd.user.services.desktop-shell-launch-profile.Unit.After;
            assert builtins.elem "desktop-shell.service"
              homeConfiguration.config.systemd.user.services.desktop-shell-launch-profile.Unit.After;
            homeConfiguration.activationPackage;

          installation-example =
            assert exampleHomeConfiguration.config.wayland.windowManager.hyprland.package == null;
            assert exampleHomeConfiguration.config.wayland.windowManager.hyprland.portalPackage == null;
            assert !exampleHomeConfiguration.config.wayland.windowManager.hyprland.systemd.enable;
            assert exampleHomeConfiguration.config.fonts.fontconfig.enable;
            assert builtins.elem (toString pkgs.fira-sans) (
              map toString exampleHomeConfiguration.config.home.packages
            );
            assert nixpkgs.lib.hasInfix "/home/desktop-shell-example/.state/desktop-shell"
              exampleHomeConfiguration.config.home.activation.seedDesktopShellState.data;
            assert builtins.elem "seedDesktopShellState"
              exampleHomeConfiguration.config.home.activation.seedDesktopShellWallpaper.after;
            pkgs.runCommand "desktop-shell-installation-example-check"
              { nativeBuildInputs = [ pkgs.hyprland ]; }
              ''
                export HOME="$TMPDIR/home"
                export XDG_RUNTIME_DIR="$TMPDIR/runtime"
                mkdir -p "$HOME"
                mkdir -m 0700 "$XDG_RUNTIME_DIR"
                test -d ${exampleHomeConfiguration.activationPackage}
                # Resolve the installed XDG link directly while checking in the build sandbox.
                substitute ${exampleHomeConfiguration.config.xdg.configFile."hypr/hyprland.lua".source} \
                  "$TMPDIR/hyprland.lua" \
                  --replace-fail ${nixpkgs.lib.escapeShellArg "${exampleHomeConfiguration.config.xdg.configHome}/desktop-shell/hyprland"} \
                  ${nixpkgs.lib.escapeShellArg "${exampleHomeConfiguration.config.programs.desktop-shell.finalPackage}/share/desktop-shell/hyprland"}
                Hyprland --verify-config --config "$TMPDIR/hyprland.lua"
                touch "$out"
              '';

          nixos-module =
            assert nixosConfiguration.config.services.greetd.enable;
            assert !nixosConfiguration.config.services.displayManager.sddm.enable;
            assert nixosConfiguration.config.services.greetd.settings.default_session.user == "greeter";
            assert nixosConfiguration.config.systemd.services.greetd.serviceConfig.Type == "simple";
            pkgs.runCommand "desktop-shell-nixos-module-check" { } ''
              touch "$out"
            '';

          nix-format =
            pkgs.runCommand "desktop-shell-nix-format"
              {
                nativeBuildInputs = [ pkgs.nixfmt ];
              }
              ''
                mapfile -t files < <(find ${self} -type f -name '*.nix' -print | sort)
                nixfmt --check "''${files[@]}"
                touch "$out"
              '';

          deadnix =
            pkgs.runCommand "desktop-shell-deadnix"
              {
                nativeBuildInputs = [ pkgs.deadnix ];
              }
              ''
                deadnix --fail ${self}
                touch "$out"
              '';

          statix =
            pkgs.runCommand "desktop-shell-statix"
              {
                nativeBuildInputs = [ pkgs.statix ];
              }
              ''
                statix check --unrestricted ${self}
                touch "$out"
              '';

          shell =
            pkgs.runCommand "desktop-shell-shell-check"
              {
                nativeBuildInputs = [
                  pkgs.shellcheck
                  pkgs.shfmt
                ];
              }
              ''
                shellcheck -x --source-path=SCRIPTDIR ${self}/src/backend/desktop-shell.sh
                mapfile -t files < <(find ${self}/src/backend ${self}/tests -type f -name '*.sh' -print | sort)
                shfmt -d -i 2 -ci "''${files[@]}"
                touch "$out"
              '';

          qml = desktopShell.passthru.qml;

          hyprland =
            pkgs.runCommand "desktop-shell-hyprland-check" { nativeBuildInputs = [ pkgs.lua5_4 ]; }
              ''
                luac -p ${self}/tests/hyprland.lua
                lua ${self}/tests/hyprland.lua ${self} ${desktopShell.passthru.hyprland}/share/desktop-shell/hyprland/init.lua
                touch "$out"
              '';

          qml-tests =
            pkgs.runCommand "desktop-shell-qml-tests"
              {
                nativeBuildInputs = [ pkgs.kdePackages.qtdeclarative ];
              }
              ''
                export HOME="$TMPDIR/home"
                export LANG=C.UTF-8
                export QT_QPA_PLATFORM=offscreen
                export XDG_CACHE_HOME="$TMPDIR/cache"
                mkdir -p "$HOME" "$XDG_CACHE_HOME"
                qmltestrunner \
                  -import ${pkgs.kdePackages.qtdeclarative}/lib/qt-6/qml \
                  -input ${self}/tests/qml
                touch "$out"
              '';

          theme-contract =
            pkgs.runCommand "desktop-shell-theme-contract-check"
              {
                nativeBuildInputs = [ pkgs.ripgrep ];
              }
              ''
                if rg -n \
                  'theme\.(foreground|text|muted|mutedAlt|blue|terminalBlue|green|yellow|orange|red|brightRed|purple)\b' \
                  ${self}/src/modules \
                  --glob '*.qml' \
                  --glob '!Theme.qml'; then
                  printf 'shell components must use semantic theme roles\n' >&2
                  exit 1
                fi
                touch "$out"
              '';

          browser-tab-bridge =
            pkgs.runCommand "desktop-shell-browser-tab-bridge-check"
              {
                nativeBuildInputs = [
                  pkgs.python3
                  pkgs.nodejs
                  pkgs.unzip
                  pkgs.web-ext
                ];
              }
              ''
                export NO_UPDATE_NOTIFIER=1
                web-ext lint \
                  --source-dir ${self}/browser-extension/extension \
                  --self-hosted \
                  --warnings-as-errors \
                  --no-config-discovery \
                  --no-input \
                  --boring
                python3 -c \
                  'source = open("${self}/browser-extension/native-host.py", encoding="utf-8").read(); compile(source, "native-host.py", "exec")'
                node ${self}/tests/browser-tab-bridge.js ${self}
                unzip -tqq ${browserTabBridge.unsignedExtension}
                touch "$out"
              '';

          cli = pkgs.runCommand "desktop-shell-cli-check" { } ''
            export HOME="$TMPDIR/home"
            export XDG_CONFIG_HOME="$TMPDIR/config"
            export XDG_STATE_HOME="$TMPDIR/state"
            export XDG_RUNTIME_DIR="$TMPDIR/runtime"
            mkdir -p "$HOME" "$XDG_RUNTIME_DIR"
            ${desktopShell}/bin/desktop-shell help | grep -F 'restart'
            ${desktopShell}/bin/desktop-shell config show | ${pkgs.jq}/bin/jq -e '.workspaces.items | length == 5'
            ${desktopShell}/bin/desktop-shell config show | ${pkgs.jq}/bin/jq -e '.keyboard.layoutLabels == ["EN"]'
            if ${desktopShell}/bin/desktop-shell definitely-not-a-command; then
              exit 1
            fi
            touch "$out"
          '';

          backend =
            pkgs.runCommand "desktop-shell-backend-check"
              {
                nativeBuildInputs = with pkgs; [
                  bash
                  coreutils
                  findutils
                  gawk
                  jq
                  util-linux
                ];
              }
              ''
                bash ${self}/tests/backend.sh \
                  ${self} \
                  ${desktopShell.passthru.payload}/share/desktop-shell/default-config.json
                touch "$out"
              '';
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              dbus
              deadnix
              jq
              kdePackages.qtdeclarative
              libnotify
              nixfmt
              (python3.withPackages (ps: [
                ps.dbus-python
                ps.pygobject3
              ]))
              quickshell
              shellcheck
              shfmt
              statix
              web-ext
            ];
          };
        }
      );

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);
    };
}
