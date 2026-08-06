{
  pkgs,
  lib ? pkgs.lib,
  source ? ../.,
  version ? "0.1.0-dev",
  hyprlandPackage ? pkgs.hyprland,
}:

let
  defaultConfig = pkgs.writeText "desktop-shell-default-config.json" (
    builtins.toJSON (import ./default-config.nix)
  );
  browserTabBridge = import ./browser-tab-bridge.nix { inherit pkgs source; };
  payload = pkgs.runCommand "desktop-shell-payload-${version}" { } ''
    mkdir -p "$out/share/desktop-shell/qml" "$out/libexec/desktop-shell"
    cp -R ${source}/src/modules "$out/share/desktop-shell/qml/modules"
    cp ${source}/src/shell.qml ${source}/src/lock.qml "$out/share/desktop-shell/qml/"
    cp -R ${source}/src/backend/. "$out/libexec/desktop-shell/"
    chmod +x "$out/libexec/desktop-shell/desktop-shell.sh"
    install -Dm0644 ${defaultConfig} "$out/share/desktop-shell/default-config.json"
  '';
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
      export DESKTOP_SHELL_QML=${lib.escapeShellArg "${payload}/share/desktop-shell/qml"}
      export DESKTOP_SHELL_DEFAULT_CONFIG=${lib.escapeShellArg "${payload}/share/desktop-shell/default-config.json"}
      export DESKTOP_SHELL_BROWSER_BRIDGE=${lib.escapeShellArg "${browserTabBridge.host}/bin/desktop-shell-browser-bridge"}
      export DESKTOP_SHELL_NOTIFICATION_SOUND=${lib.escapeShellArg "${pkgs.sound-theme-freedesktop}/share/sounds/freedesktop/stereo/message-new-instant.oga"}
      export DESKTOP_SHELL_VERSION=${lib.escapeShellArg version}

      exec ${pkgs.bash}/bin/bash ${payload}/libexec/desktop-shell/desktop-shell.sh "$@"
    '';
  };
in
pkgs.symlinkJoin {
  name = "desktop-shell-${version}";
  paths = [
    cli
    payload
  ];
  passthru = {
    inherit browserTabBridge payload version;
  };
  meta = {
    description = "A keyboard-first Quickshell desktop shell for Hyprland";
    license = lib.licenses.gpl3Plus;
    mainProgram = "desktop-shell";
    platforms = lib.platforms.linux;
  };
}
