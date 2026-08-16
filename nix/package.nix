{
  pkgs,
  lib ? pkgs.lib,
  source ? ../.,
  hyprlandPackage ? pkgs.hyprland,
}:

let
  sources = import ./source-files.nix { inherit lib source; };
  defaultConfig = pkgs.writeText "desktop-shell-default-config.json" (
    builtins.toJSON (import ./default-config.nix)
  );
  browserTabBridge = import ./browser-tab-bridge.nix { inherit pkgs source; };
  qml =
    pkgs.runCommand "desktop-shell-qml"
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
        done < <(find ${sources.qml}/src -type f -name '*.qml' -print0)
        test "$status" -eq 0

        mkdir -p "$out/share/desktop-shell/qml"
        cp -R ${sources.qml}/src/modules "$out/share/desktop-shell/qml/modules"
        cp \
          ${sources.qml}/src/greeter.qml \
          ${sources.qml}/src/lock.qml \
          ${sources.qml}/src/shell.qml \
          "$out/share/desktop-shell/qml/"
      '';
  backend = pkgs.runCommand "desktop-shell-backend" { } ''
    mkdir -p "$out/libexec/desktop-shell"
    cp -R ${sources.backend}/src/backend/. "$out/libexec/desktop-shell/"
    chmod +x "$out/libexec/desktop-shell/desktop-shell.sh"
  '';
  configPayload = pkgs.runCommand "desktop-shell-config" { } ''
    mkdir -p "$out/share/desktop-shell"
    install -Dm0644 ${defaultConfig} "$out/share/desktop-shell/default-config.json"
  '';
  payload = pkgs.symlinkJoin {
    name = "desktop-shell-payload";
    paths = [
      qml
      backend
      configPayload
    ];
  };
  cli = pkgs.writeShellApplication {
    name = "desktop-shell";
    runtimeInputs =
      with pkgs;
      [
        brightnessctl
        bluez
        cliphist
        coreutils
        ddcutil
        findutils
        gawk
        gnugrep
        gnused
        jq
        pamixer
        pipewire
        procps
        quickshell
        systemd
        util-linux
        uwsm
        wl-clipboard
      ]
      ++ [ hyprlandPackage ];
    text = ''
      export LC_ALL=C.UTF-8
      export DESKTOP_SHELL_EXECUTABLE="$0"
      export DESKTOP_SHELL_QML=${lib.escapeShellArg "${qml}/share/desktop-shell/qml"}
      export DESKTOP_SHELL_DEFAULT_CONFIG=${lib.escapeShellArg "${configPayload}/share/desktop-shell/default-config.json"}
      export DESKTOP_SHELL_BROWSER_BRIDGE=${lib.escapeShellArg "${browserTabBridge.host}/bin/desktop-shell-browser-bridge"}
      export DESKTOP_SHELL_NOTIFICATION_SOUND=${lib.escapeShellArg "${pkgs.sound-theme-freedesktop}/share/sounds/freedesktop/stereo/message-new-instant.oga"}
      exec ${pkgs.bash}/bin/bash ${backend}/libexec/desktop-shell/desktop-shell.sh "$@"
    '';
  };
in
pkgs.symlinkJoin {
  name = "desktop-shell";
  paths = [
    cli
    payload
  ];
  passthru = {
    inherit
      backend
      browserTabBridge
      configPayload
      payload
      qml
      ;
  };
  meta = {
    description = "A keyboard-first Quickshell desktop shell for Hyprland";
    license = lib.licenses.gpl3Plus;
    mainProgram = "desktop-shell";
    platforms = lib.platforms.linux;
  };
}
