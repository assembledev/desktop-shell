{
  pkgs,
  source ? ../.,
}:

let
  extensionId = "desktop-shell-tabs@desktop-shell.local";
  nativeHostName = "io.desktop_shell.browser_tabs";
  host = pkgs.writeShellApplication {
    name = "desktop-shell-browser-bridge";
    text = ''
      exec ${pkgs.python3}/bin/python3 ${source}/browser-extension/native-host.py "$@"
    '';
  };
  nativeManifest = pkgs.writeText "${nativeHostName}.json" (
    builtins.toJSON {
      name = nativeHostName;
      description = "Desktop Shell browser tab bridge";
      path = "${host}/bin/desktop-shell-browser-bridge";
      type = "stdio";
      allowed_extensions = [ extensionId ];
    }
  );
  nativeMessagingHost = pkgs.runCommand "desktop-shell-browser-native-messaging-host" { } ''
    install -Dm0644 ${nativeManifest} \
      "$out/lib/mozilla/native-messaging-hosts/${nativeHostName}.json"
  '';
  unsignedExtension =
    pkgs.runCommand "desktop-shell-tabs-unsigned.xpi"
      {
        nativeBuildInputs = [ pkgs.zip ];
      }
      ''
        cd ${source}/browser-extension/extension
        zip -q -r "$out" .
      '';
in
{
  inherit
    extensionId
    host
    nativeHostName
    nativeMessagingHost
    unsignedExtension
    ;
}
