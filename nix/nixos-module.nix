{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.desktop-shell;
  greeterCfg = cfg.greeter;
  defaultPackage = import ./package.nix {
    inherit pkgs;
    source = ../.;
  };
  greeterQml = cfg.package.passthru.qml or cfg.package;
  greeterCursorSize = builtins.ceil (24 * greeterCfg.scale);
  sessionLauncher = pkgs.writeShellScript "desktop-shell-session" ''
    exec ${lib.escapeShellArgs greeterCfg.sessionCommand}
  '';
  greeterLauncher = pkgs.writeShellScript "desktop-shell-greeter" ''
    export HOME=/run/desktop-shell-greeter
    export XDG_CACHE_HOME="$HOME/cache"
    export XDG_CONFIG_HOME="$HOME/config"
    export XDG_DATA_HOME="$HOME/data"
    export XDG_RUNTIME_DIR="$HOME/runtime"
    export XDG_STATE_HOME="$HOME/state"
    ${pkgs.coreutils}/bin/install -d -m 0700 \
      "$XDG_CACHE_HOME" \
      "$XDG_CONFIG_HOME" \
      "$XDG_DATA_HOME" \
      "$XDG_RUNTIME_DIR" \
      "$XDG_STATE_HOME"

    export LANG=en_US.UTF-8
    export LANGUAGE=en
    export LC_ALL=en_US.UTF-8
    export QT_QPA_PLATFORM=wayland
    export QT_SCALE_FACTOR=${lib.escapeShellArg (toString greeterCfg.scale)}
    export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
    export XCURSOR_PATH=${lib.escapeShellArg "${greeterCfg.cursorPackage}/share/icons"}
    export XCURSOR_SIZE=${lib.escapeShellArg (toString greeterCursorSize)}
    export XCURSOR_THEME=${lib.escapeShellArg greeterCfg.cursorTheme}
    export XKB_DEFAULT_LAYOUT=us
    export XKB_DEFAULT_OPTIONS=
    export XKB_DEFAULT_VARIANT=
    export DESKTOP_SHELL_GREETER_USER=${lib.escapeShellArg greeterCfg.user}
    export DESKTOP_SHELL_GREETER_SESSION=${lib.escapeShellArg sessionLauncher}
    export DESKTOP_SHELL_GREETER_WALLPAPER=${lib.escapeShellArg greeterCfg.wallpaperPath}
    export DESKTOP_SHELL_THEME_JSON=${lib.escapeShellArg (builtins.toJSON greeterCfg.theme)}

    exec ${pkgs.dbus}/bin/dbus-run-session \
      ${lib.getExe pkgs.cage} -s -d -m ${lib.escapeShellArg greeterCfg.outputMode} -- \
      ${lib.getExe pkgs.quickshell} \
        --log-rules '*.info=false' \
        --path ${greeterQml}/share/desktop-shell/qml/greeter.qml
  '';
in
{
  options.programs.desktop-shell = {
    enable = lib.mkEnableOption "NixOS support for Desktop Shell";

    package = lib.mkOption {
      type = lib.types.package;
      default = defaultPackage;
      defaultText = lib.literalExpression "Desktop Shell package built from the module source";
      description = "Desktop Shell package used by system-level integrations.";
    };

    lock.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Create the PAM service used by the session lock.";
    };

    greeter = {
      enable = lib.mkEnableOption "the Desktop Shell greetd greeter";

      user = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Fixed local user authenticated by the greeter.";
      };

      scale = lib.mkOption {
        type = lib.types.numbers.positive;
        default = 1;
        description = "Qt scale factor used by the greeter.";
      };

      cursorPackage = lib.mkOption {
        type = lib.types.package;
        default = pkgs.bibata-cursors;
        defaultText = lib.literalExpression "pkgs.bibata-cursors";
        description = "Package providing the greeter cursor theme.";
      };

      cursorTheme = lib.mkOption {
        type = lib.types.nonEmptyStr;
        default = "Bibata-Modern-Ice";
        description = "Cursor theme used by the greeter.";
      };

      outputMode = lib.mkOption {
        type = lib.types.enum [
          "last"
          "extend"
        ];
        default = "last";
        description = "Cage output mode; last uses only the final discovered output.";
      };

      wallpaperPath = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Greeter-readable absolute path to the cached wallpaper.";
      };

      sessionCommand = lib.mkOption {
        type = lib.types.nonEmptyListOf lib.types.str;
        default = [
          (lib.getExe' pkgs.coreutils "env")
          "UWSM_SILENT_START=1"
          (lib.getExe pkgs.uwsm)
          "start"
          "-e"
          "-D"
          "Hyprland"
          "hyprland.desktop"
        ];
        defaultText = lib.literalExpression ''
          [ "''${lib.getExe' pkgs.coreutils "env"}" "UWSM_SILENT_START=1" "''${lib.getExe pkgs.uwsm}" "start" "-e" "-D" "Hyprland" "hyprland.desktop" ]
        '';
        description = "Fixed command launched after successful authentication.";
      };

      theme = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = import ./theme.nix;
        defaultText = lib.literalExpression "import ./theme.nix";
        description = "Theme values passed to the greeter's shared LockView.";
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf (cfg.enable && cfg.lock.enable) {
      security.pam.services.desktop-shell-lock = { };
    })

    (lib.mkIf (cfg.enable && greeterCfg.enable) {
      assertions = [
        {
          assertion = greeterCfg.user != "";
          message = "programs.desktop-shell.greeter.user must name the local login user";
        }
        {
          assertion = !config.services.displayManager.sddm.enable;
          message = "Desktop Shell's greetd greeter and SDDM cannot both be enabled";
        }
      ];

      fonts.packages = [ pkgs.nerd-fonts.fira-code ];

      services.greetd = {
        enable = true;
        settings.default_session = {
          command = greeterLauncher;
          user = "greeter";
        };
      };

      # A graphical greeter owns the console as soon as it starts. Avoid the
      # Type=idle delay intended to keep text login prompts behind boot output.
      systemd.services.greetd.serviceConfig.Type = lib.mkForce "simple";

      # Quickshell needs a writable home and runtime directory while authenticating.
      systemd.tmpfiles.rules = [
        "d /run/desktop-shell-greeter 0700 greeter greeter -"
      ];
    })
  ];
}
