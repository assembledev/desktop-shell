"""Exercise the real Qt portal helper on a private bus; no desktop dialogs or transfers."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


if len(sys.argv) == 1:
    with tempfile.TemporaryDirectory(prefix="taildrop-save-") as temporary:
        root = Path(temporary)
        config = root / "dbus.conf"
        config.write_text('''<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN" "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig><type>session</type><listen>unix:tmpdir=/tmp</listen>
<policy context="default"><allow own="*"/><allow send_destination="*"/><allow send_type="signal"/><allow receive_sender="*"/></policy>
</busconfig>''')
        sys.exit(subprocess.call([
            "dbus-run-session", "--config-file=" + str(config), "--",
            sys.executable, __file__, str(root),
        ]))

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

root = Path(sys.argv[1])
source = Path(__file__).resolve().parents[2]
shutil.copytree(source / "src/modules", root / "modules")
# Only the layer-surface container needs Wayland. Keep the production save flow
# and real native FileDialog, with a hidden window as its offscreen parent.
(root / "modules/common/BarOverlayWindow.qml").write_text("""import QtQuick
import QtQuick.Window
Window {
  required property var barSurface
  property var targetScreen: null
  required property bool requested
  required property bool presented
  required property string surfaceNamespace
  property bool keyboardRequested: false
  visible: false
}
""")
shutil.copyfile(source / "tests/native/taildrop-save.qml", root / "shell.qml")
for directory in ["home/Downloads", "runtime", "data", "config", "saved"]:
    (root / directory).mkdir(parents=True, exist_ok=True)
(root / "runtime").chmod(0o700)
backend = root / "backend"
backend.write_text(f"#!{sys.executable}\n" + """import json
import os
import sys
with open(os.environ["TEST_SAVE_LOG"], "a") as output:
    output.write(json.dumps(sys.argv[1:]) + "\\n")
print('{"saved":true,"inboxRemoved":true}')
""")
backend.chmod(0o700)
names = ["readme.md", "archive.tar.gz", "cancelled.txt", "résumé #%20 [draft].tar.gz"]
seen = []
failure = []
DBusGMainLoop(set_as_default=True)
bus = dbus.SessionBus()
owner = dbus.service.BusName("org.freedesktop.portal.Desktop", bus)


class Request(dbus.service.Object):
    @dbus.service.signal("org.freedesktop.portal.Request", signature="ua{sv}")
    def Response(self, code, results):
        pass


class Portal(dbus.service.Object):
    @dbus.service.method("org.freedesktop.DBus.Properties", in_signature="ss", out_signature="v")
    def Get(self, interface, key):
        return dbus.UInt32(4, variant_level=1)

    @dbus.service.method("org.freedesktop.portal.Settings", in_signature="as", out_signature="a{sa{sv}}")
    def ReadAll(self, namespaces):
        return {}

    @dbus.service.method("org.freedesktop.portal.FileChooser", in_signature="ssa{sv}", out_signature="o")
    def SaveFile(self, parent, title, options):
        name = str(options.get("current_name", ""))
        expected = names[len(seen)]
        seen.append(name)
        folder = bytes(options.get("current_folder", [])).rstrip(b"\0").decode()
        if folder != str(root / "home/Downloads"):
            failure.append(f"SaveFile {len(seen)} suggested the wrong directory: {folder!r}")
        if name != expected:
            failure.append(f"SaveFile {len(seen)} suggested {name!r}, expected {expected!r}")
        request_path = "/org/freedesktop/portal/desktop/request/test/save" + str(len(seen))
        request = Request(bus, request_path)
        requests.append(request)
        result = dbus.Dictionary({"uris": dbus.Array([(root / "saved" / name).as_uri()], signature="s")}, signature="sv")
        GLib.timeout_add(50, lambda: request.Response(1 if expected == "cancelled.txt" else 0, result))
        return request_path


requests = []
portal = Portal(bus, "/org/freedesktop/portal/desktop")
env = dict(os.environ)
for key in ["WAYLAND_DISPLAY", "DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE"]:
    env.pop(key, None)
env.update({
    "HOME": str(root / "home"), "XDG_RUNTIME_DIR": str(root / "runtime"),
    "XDG_DATA_HOME": str(root / "data"), "XDG_DATA_DIRS": str(root / "data"),
    "XDG_CONFIG_HOME": str(root / "config"), "QT_QPA_PLATFORM": "offscreen",
    "QT_QPA_PLATFORMTHEME": "xdgdesktopportal", "DESKTOP_SHELL_TEST_BACKEND": str(backend),
    "TEST_SAVE_LOG": str(root / "save-log"),
})
process = subprocess.Popen(["quickshell", "--no-color", "--path", str(root / "shell.qml")], env=env)
loop = GLib.MainLoop()


def poll():
    if process.poll() is None:
        return True
    loop.quit()
    return False


GLib.timeout_add(50, poll)
try:
    loop.run()
finally:
    if process.poll() is None:
        process.terminate()
        process.wait(timeout=2)
assert not failure, "; ".join(failure)
assert process.returncode == 0, f"Quickshell exited {process.returncode}; requests: {seen}"
assert seen == names, seen
commands = [json.loads(line) for line in (root / "save-log").read_text().splitlines()]
accepted = [name for name in names if name != "cancelled.txt"]
assert commands == [["tailscale", "receive", name, str(root / "saved" / name)] for name in accepted], commands
print("PASS real portal requests and receive destinations preserve each incoming filename")
