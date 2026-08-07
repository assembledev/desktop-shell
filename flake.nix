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
                };
              }
            ];
          };
        in
        {
          package = desktopShell;
          home-manager = homeConfiguration.activationPackage;

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

          qml =
            pkgs.runCommand "desktop-shell-qml-check"
              {
                nativeBuildInputs = [ pkgs.kdePackages.qtdeclarative ];
              }
              ''
                export LANG=C.UTF-8
                status=0
                while IFS= read -r -d $'\0' file; do
                  qmllint \
                    --ignore-settings \
                    --import error \
                    --unqualified disable \
                    --missing-property disable \
                    --incompatible-type disable \
                    --uncreatable-type disable \
                    -I ${pkgs.kdePackages.qtdeclarative}/lib/qt-6/qml \
                    -I ${pkgs.quickshell}/lib/qt-6/qml \
                    "$file" || status=1
                done < <(find ${self}/src -type f -name '*.qml' -print0)
                test "$status" -eq 0
                touch "$out"
              '';

          browser-tab-bridge =
            pkgs.runCommand "desktop-shell-browser-tab-bridge-check"
              {
                nativeBuildInputs = [
                  pkgs.python3
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
                  jq
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
              deadnix
              kdePackages.qtdeclarative
              nixfmt
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
