{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;
  cfg = config.programs.desktop-shell;
  defaultConfig = import ./default-config.nix;
  defaultTheme = import ./theme.nix;

  workspaceType = types.submodule {
    options = {
      id = mkOption {
        type = types.ints.positive;
        description = "Hyprland workspace ID.";
      };
      label = mkOption {
        type = types.str;
        description = "Label shown in the bar and workspace overview.";
      };
      x = mkOption {
        type = types.int;
        description = "Horizontal coordinate used by spatial navigation.";
      };
      y = mkOption {
        type = types.int;
        default = 0;
        description = "Vertical coordinate used by spatial navigation.";
      };
    };
  };

  networkControlType = types.submodule {
    options = {
      id = mkOption {
        type = types.strMatching "^[A-Za-z0-9_.-]+$";
        description = "Stable provider identifier.";
      };
      label = mkOption {
        type = types.str;
        description = "Fallback label shown in the bar.";
      };
      icon = mkOption {
        type = types.str;
        default = "";
        description = "Icon path or URL understood by QML Image.";
      };
      statusCommand = mkOption {
        type = types.listOf types.str;
        description = "Argv command returning a JSON status object.";
      };
      toggleCommand = mkOption {
        type = types.listOf types.str;
        description = "Argv command toggling the provider.";
      };
    };
  };

  hotkeyType = types.submodule {
    options = {
      key = mkOption { type = types.str; };
      title = mkOption { type = types.str; };
      category = mkOption {
        type = types.str;
        default = "Other";
      };
      description = mkOption {
        type = types.str;
        default = "";
      };
      hidden = mkOption {
        type = types.bool;
        default = false;
      };
    };
  };

  colorType = types.strMatching "^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$";
  themeOptions = lib.mapAttrs (
    name: value:
    mkOption {
      type = if name == "fontFamily" then types.str else colorType;
      default = value;
      description = "Desktop Shell ${name} theme value.";
    }
  ) defaultTheme;

  generatedConfig = {
    workspaces = {
      items = cfg.workspaces.items;
      scrolling = cfg.workspaces.scrolling;
    };
    inherit (cfg) output;
    wallpaper = {
      inherit (cfg.wallpaper) directory default;
    };
    bar = {
      inherit (cfg.bar)
        compact
        networkControls
        showVram
        workspaceIcons
        ;
    };
    keyboard.layoutLabels = cfg.keyboard.layoutLabels;
    browserTabs = {
      inherit (cfg.browserTabs)
        desktopEntryId
        displayName
        enable
        icon
        ;
    };
    lock.keyboardLayoutIndex = cfg.lock.keyboardLayoutIndex;
    integrations = {
      inherit (cfg.integrations)
        hotkeys
        privilegedHelper
        recordingStateFile
        sddmWallpaperSync
        ;
    };
    inherit (cfg) theme;
  };
  configFile = pkgs.writeText "desktop-shell-config.json" (builtins.toJSON generatedConfig);
  finalPackage =
    if cfg.package != null then
      cfg.package
    else
      import ./package.nix {
        inherit pkgs;
        source = ../.;
        inherit (cfg) hyprlandPackage;
      };
  command = "${finalPackage}/bin/desktop-shell";
  serviceTarget = cfg.systemd.target;
in
{
  options.programs.desktop-shell = {
    enable = mkEnableOption "Desktop Shell";

    package = mkOption {
      type = types.nullOr types.package;
      default = null;
      description = "Desktop Shell package; null builds the package from this module.";
    };

    hyprlandPackage = mkOption {
      type = types.package;
      default = pkgs.hyprland;
      defaultText = lib.literalExpression "pkgs.hyprland";
      description = "Hyprland package whose hyprctl is placed on the shell PATH.";
    };

    finalPackage = mkOption {
      type = types.package;
      readOnly = true;
      description = "Resolved package used by the module.";
    };

    systemd = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Run Desktop Shell as a systemd user service.";
      };
      target = mkOption {
        type = types.str;
        default = "graphical-session.target";
        description = "User target that owns the shell service.";
      };
    };

    workspaces = {
      items = mkOption {
        type = types.nonEmptyListOf workspaceType;
        default = defaultConfig.workspaces.items;
        description = "Ordered workspace topology used by all shell surfaces.";
      };
      scrolling = mkOption {
        type = types.nullOr types.ints.positive;
        default = null;
        description = "Workspace using scrolling/tape navigation, if any.";
      };
    };

    output = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Output name for shell surfaces; null uses Quickshell's default screen.";
    };

    wallpaper = {
      directory = mkOption {
        type = types.str;
        default = "${config.home.homeDirectory}/Wallpapers";
        description = "Directory scanned by the wallpaper picker.";
      };
      default = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Wallpaper seeded and used when no choice has been saved.";
      };
    };

    bar = {
      compact = mkOption {
        type = types.bool;
        default = false;
      };
      showVram = mkOption {
        type = types.bool;
        default = true;
      };
      workspaceIcons = mkOption {
        type = types.bool;
        default = true;
      };
      networkControls = mkOption {
        type = types.listOf networkControlType;
        default = [ ];
        description = "Trusted generic status/toggle providers shown in the bar.";
      };
    };

    keyboard.layoutLabels = mkOption {
      type = types.nonEmptyListOf (types.strMatching "^.{1,4}$");
      default = defaultConfig.keyboard.layoutLabels;
      description = "Short labels indexed in the same order as the compositor keyboard layouts.";
    };

    browserTabs = {
      enable = mkEnableOption "the experimental Firefox-compatible browser tab bridge";
      desktopEntryId = mkOption {
        type = types.str;
        default = "firefox";
      };
      displayName = mkOption {
        type = types.str;
        default = "Firefox";
      };
      icon = mkOption {
        type = types.str;
        default = "firefox";
      };
    };

    lock.keyboardLayoutIndex = mkOption {
      type = types.nullOr types.ints.unsigned;
      default = null;
      description = "Keyboard layout selected while locked; null preserves the active layout.";
    };

    integrations = {
      hotkeys = mkOption {
        type = types.listOf hotkeyType;
        default = [ ];
        description = "Entries displayed by the in-shell cheatsheet.";
      };
      privilegedHelper = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      recordingStateFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Optional absolute path, or filename below XDG_RUNTIME_DIR, containing a recording start timestamp.";
      };
      sddmWallpaperSync = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
    };

    theme = themeOptions;

    clipboard.watch.enable = mkOption {
      type = types.bool;
      default = true;
      description = "Store text and image clipboard changes through cliphist.";
    };

    bluetooth.agent.enable = mkOption {
      type = types.bool;
      default = true;
      description = "Run Blueman as the pairing agent without a duplicate tray icon.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion =
          let
            ids = map (workspace: workspace.id) cfg.workspaces.items;
          in
          builtins.length ids == builtins.length (lib.unique ids);
        message = "programs.desktop-shell.workspaces.items must use unique IDs";
      }
      {
        assertion =
          cfg.workspaces.scrolling == null
          || lib.any (workspace: workspace.id == cfg.workspaces.scrolling) cfg.workspaces.items;
        message = "programs.desktop-shell.workspaces.scrolling must name a configured workspace";
      }
      {
        assertion = lib.all (
          provider: provider.statusCommand != [ ] && provider.toggleCommand != [ ]
        ) cfg.bar.networkControls;
        message = "Desktop Shell network provider commands must not be empty";
      }
    ];

    programs.desktop-shell.finalPackage = finalPackage;
    home = {
      packages = [
        finalPackage
        pkgs.nerd-fonts.fira-code
      ];

      activation.seedDesktopShellState = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        $DRY_RUN_CMD mkdir -p "$HOME/.local/state/desktop-shell/wallpaper"
        $DRY_RUN_CMD mkdir -p "$HOME/.local/state/desktop-shell/preferences"
        for preference in dnd focus; do
          legacy="$HOME/.local/state/desktop-shell/$preference"
          target="$HOME/.local/state/desktop-shell/preferences/$preference"
          if [ ! -e "$target" ] && [ -r "$legacy" ]; then
            $DRY_RUN_CMD cp "$legacy" "$target"
          fi
        done
        $DRY_RUN_CMD mkdir -p ${lib.escapeShellArg cfg.wallpaper.directory}
      '';

      activation.seedDesktopShellWallpaper = mkIf (cfg.wallpaper.default != null) (
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          if [ ! -e ${lib.escapeShellArg "${cfg.wallpaper.directory}/wallpaper.jpg"} ]; then
            $DRY_RUN_CMD cp ${cfg.wallpaper.default} ${lib.escapeShellArg "${cfg.wallpaper.directory}/wallpaper.jpg"}
          fi
        ''
      );
    };

    xdg.configFile."desktop-shell/config.json".source = configFile;

    systemd.user.services = {
      desktop-shell = mkIf cfg.systemd.enable {
        Unit = {
          Description = "Quickshell desktop shell";
          ConditionEnvironment = "WAYLAND_DISPLAY";
          After = [ serviceTarget ];
          PartOf = [ serviceTarget ];
          StartLimitIntervalSec = 60;
          StartLimitBurst = 3;
          X-SwitchMethod = "restart";
          X-Restart-Triggers = [
            configFile
            finalPackage
          ];
        };
        Service = {
          ExecStart = "${command} run";
          ExecStartPost = "${command} wait-ready";
          Restart = "on-failure";
          RestartSec = 1;
          TimeoutStartSec = 8;
          TimeoutStopSec = 5;
        };
        Install.WantedBy = [ serviceTarget ];
      };

      desktop-shell-bluetooth-private = mkIf cfg.systemd.enable {
        Unit = {
          Description = "Establish Desktop Shell Bluetooth privacy baseline";
          ConditionEnvironment = "WAYLAND_DISPLAY";
          After = [ serviceTarget ];
          PartOf = [ serviceTarget ];
          X-SwitchMethod = "restart";
          X-Restart-Triggers = [ finalPackage ];
        };
        Service = {
          Type = "oneshot";
          ExecStart = "${command} bluetooth session-close";
          RemainAfterExit = true;
          TimeoutStartSec = 2;
        };
        Install.WantedBy = [ serviceTarget ];
      };

      desktop-shell-clipboard-text = mkIf cfg.clipboard.watch.enable {
        Unit = {
          Description = "Desktop Shell text clipboard watcher";
          ConditionEnvironment = "WAYLAND_DISPLAY";
          After = [ serviceTarget ];
          PartOf = [ serviceTarget ];
        };
        Service = {
          ExecStart = "${pkgs.wl-clipboard}/bin/wl-paste --type text --watch ${pkgs.bash}/bin/bash -c '${pkgs.cliphist}/bin/cliphist store && ${command} clipboard refresh'";
          Restart = "on-failure";
          RestartSec = 1;
        };
        Install.WantedBy = [ serviceTarget ];
      };

      desktop-shell-clipboard-image = mkIf cfg.clipboard.watch.enable {
        Unit = {
          Description = "Desktop Shell image clipboard watcher";
          ConditionEnvironment = "WAYLAND_DISPLAY";
          After = [ serviceTarget ];
          PartOf = [ serviceTarget ];
        };
        Service = {
          ExecStart = "${pkgs.wl-clipboard}/bin/wl-paste --type image --watch ${pkgs.bash}/bin/bash -c '${pkgs.cliphist}/bin/cliphist store && ${command} clipboard refresh'";
          Restart = "on-failure";
          RestartSec = 1;
        };
        Install.WantedBy = [ serviceTarget ];
      };

      blueman-applet = mkIf cfg.bluetooth.agent.enable {
        Unit = {
          Description = "Bluetooth pairing agent";
          ConditionEnvironment = "WAYLAND_DISPLAY";
          After = [ serviceTarget ];
          PartOf = [ serviceTarget ];
        };
        Service = {
          ExecStart = "${pkgs.blueman}/bin/blueman-applet";
          Restart = "on-failure";
          RestartSec = 2;
        };
        Install.WantedBy = [ serviceTarget ];
      };
    };

    dconf.settings."org/blueman/general".plugin-list = mkIf cfg.bluetooth.agent.enable [
      "!ShowConnected"
      "!StatusIcon"
      "!StatusNotifierItem"
    ];
    xdg.configFile."autostart/blueman.desktop" = mkIf cfg.bluetooth.agent.enable {
      text = ''
        [Desktop Entry]
        Type=Application
        Hidden=true
      '';
    };

  };
}
