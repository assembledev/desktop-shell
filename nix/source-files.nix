{
  lib,
  source,
}:

let
  select =
    fileset:
    lib.fileset.toSource {
      root = source;
      inherit fileset;
    };
in
{
  backend = select (source + "/src/backend");
  qml = select (
    lib.fileset.unions [
      (source + "/src/modules")
      (source + "/src/greeter.qml")
      (source + "/src/lock.qml")
      (source + "/src/shell.qml")
    ]
  );
  browserHost = select (source + "/browser-extension/native-host.py");
  browserExtension = select (source + "/browser-extension/extension");
}
