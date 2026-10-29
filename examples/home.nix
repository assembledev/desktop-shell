# Import alongside desktop-shell.homeManagerModules.default in an existing home.
{ config, lib, ... }:
let
  shell = lib.getExe config.programs.desktop-shell.finalPackage;
in
{
  programs.desktop-shell = {
    enable = true;
    integrations.hotkeys = [
      {
        key = "ALT + SPACE";
        title = "Launcher";
      }
      {
        key = "SUPER + N";
        title = "Control center";
      }
      {
        key = "SUPER + V";
        title = "Clipboard history";
      }
      {
        key = "SUPER + W";
        title = "Wallpapers";
      }
      {
        key = "SUPER + slash";
        title = "Keybindings";
      }
      {
        key = "SUPER + L";
        title = "Lock";
      }
      {
        key = "ALT + TAB";
        title = "Switch windows";
      }
    ];
  };

  services.hyprpaper = {
    enable = true;
    settings.splash = false;
  };

  wayland.windowManager.hyprland = {
    enable = true;
    configType = "lua";
    # NixOS owns the compositor package, portals and UWSM session.
    package = null;
    portalPackage = null;
    systemd.enable = false;

    extraConfig = ''
      hl.on("hyprland.start", function()
        hl.exec_cmd("${shell} apply")
      end)

      hl.bind("ALT + SPACE", hl.dsp.exec_cmd("${shell} launcher toggle"))
      hl.bind("SUPER + N", hl.dsp.exec_cmd("${shell} toggle"))
      hl.bind("SUPER + V", hl.dsp.exec_cmd("${shell} clipboard open"))
      hl.bind("SUPER + W", hl.dsp.exec_cmd("${shell} pick"))
      hl.bind("SUPER + slash", hl.dsp.exec_cmd("${shell} cheatsheet toggle"))
      hl.bind("SUPER + L", hl.dsp.exec_cmd("${shell} lock"))

      hl.bind("ALT + TAB", hl.dsp.exec_cmd("${shell} alttab next"))
      hl.bind("ALT + SHIFT + TAB", hl.dsp.exec_cmd("${shell} alttab prev"))
      hl.bind("ALT + ALT_L", hl.dsp.exec_cmd("${shell} alttab commit"), {
        release = true, transparent = true, ignore_mods = true,
      })
      hl.bind("ALT + ALT_R", hl.dsp.exec_cmd("${shell} alttab commit"), {
        release = true, transparent = true, ignore_mods = true,
      })
    '';
  };
}
