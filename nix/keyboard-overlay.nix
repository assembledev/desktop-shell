{ pkgs, source }:
pkgs.rustPlatform.buildRustPackage {
  pname = "desktop-shell-keyboard";
  version = "0.1.0";
  src = source + "/src/keyboard-overlay";
  cargoLock = {
    lockFile = source + "/src/keyboard-overlay/Cargo.lock";
    outputHashes."rynk-0.3.0" = "sha256-k5PRQU4nYWXPzkDfbpeHv3eX35/aVMZIXeZE6e3M+Ds=";
  };
  nativeBuildInputs = [ pkgs.pkg-config ];
  buildInputs = [ pkgs.dbus ];
  meta = {
    description = "Read-only Glove80 layer state for Desktop Shell";
    license = pkgs.lib.licenses.gpl3Plus;
    platforms = pkgs.lib.platforms.linux;
  };
}
