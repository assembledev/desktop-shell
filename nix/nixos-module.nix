{
  config,
  lib,
  ...
}:

let
  cfg = config.programs.desktop-shell;
in
{
  options.programs.desktop-shell = {
    enable = lib.mkEnableOption "NixOS support for Desktop Shell";
    lock.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Create the PAM service used by the session lock.";
    };
  };

  config = lib.mkIf (cfg.enable && cfg.lock.enable) {
    security.pam.services.desktop-shell-lock = { };
  };
}
