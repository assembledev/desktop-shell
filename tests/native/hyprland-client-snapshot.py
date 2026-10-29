"""Run in the dev shell: python3 tests/native/hyprland-client-snapshot.py."""
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import threading
import time

source = Path(__file__).resolve().parents[2] / "src/modules/common/HyprlandClientSnapshot.qml"
first, second = [{"title": "Привет 😀"}], [{"title": "Второй 🦊"}]
cases = [(json.dumps(value, ensure_ascii=False).encode(), value) for value in [first, second]]
cases += [(b"garbage", "invalid clients response:"), (b"{}", "invalid clients response:"),
          (b"[{", "invalid clients response:"), (None, "clients request timed out")]
cases += [(json.dumps(first, ensure_ascii=False).encode(), first), (b"[]", [])]

with tempfile.TemporaryDirectory(prefix="snapshot-test-") as temporary:
    root = Path(temporary)
    for directory in ["home", "runtime", "config", "cache", "state", "data"]:
        (root / directory).mkdir(mode=0o700)
    # Remove the singleton import as well as its socket path: this fixture must
    # never connect to the running compositor, even during module initialization.
    component = source.read_text().replace("import Quickshell.Hyprland\n", "")
    component = component.replace("Hyprland.requestSocketPath", 'Quickshell.env("TEST_SOCKET")')
    assert "Hyprland." not in component
    (root / "Snapshot.qml").write_text(component)
    (root / "shell.qml").write_text('''import QtQuick
import Quickshell
ShellRoot {
  id: root
  property int index: 0
  function next() {
    console.log("SNAPSHOT_START", index);
    if (!snapshot.request() || snapshot.request()) {
      console.error("request admission failed"); Qt.quit();
    }
  }
  function record(clients, reason) {
    console.log("SNAPSHOT_RESULT", JSON.stringify({clients, reason, pending: snapshot.pending}));
    if (++index === ''' + str(len(cases)) + ''') Qt.quit();
    else Qt.callLater(next);
  }
  Snapshot {
    id: snapshot
    onSucceeded: clients => root.record(clients, "")
    onFailed: reason => root.record(null, reason)
  }
  Component.onCompleted: next()
}
''')
    failures = []
    listener = socket.socket(socket.AF_UNIX)
    listener.bind(str(root / "socket"))
    listener.listen(1)
    listener.settimeout(3)

    def serve():
        try:
            for payload, expected in cases:
                connection, _ = listener.accept()
                with connection:
                    connection.settimeout(2)
                    request = b""
                    while len(request) < len(b"j/clients"):
                        part = connection.recv(256)
                        assert part, "client disconnected before sending its request"
                        request += part
                    assert request == b"j/clients", request
                    if payload is not None:
                        # Deliver each byte separately, including within UTF-8 code points.
                        for byte in payload:
                            connection.sendall(bytes([byte]))
                            time.sleep(0.004)
                    if isinstance(expected, list) or payload is None:
                        assert connection.recv(1) == b"", "client did not close after success/timeout"
        except Exception as error:
            failures.append(repr(error))
        finally:
            listener.close()

    server = threading.Thread(target=serve, daemon=True)
    server.start()
    env = {"PATH": os.environ["PATH"], "LANG": "C.UTF-8", "QT_QPA_PLATFORM": "offscreen",
           "HOME": str(root / "home"), "TEST_SOCKET": str(root / "socket"),
           "DBUS_SESSION_BUS_ADDRESS": "unix:path=" + str(root / "no-bus"),
           "DBUS_SYSTEM_BUS_ADDRESS": "unix:path=" + str(root / "no-bus")}
    env.update({"XDG_" + name + "_HOME": str(root / name.lower())
                for name in ["CONFIG", "CACHE", "STATE", "DATA"]})
    env["XDG_RUNTIME_DIR"] = str(root / "runtime")
    result = subprocess.run(["quickshell", "--no-color", "--path", str(root / "shell.qml")],
                            env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=8)
    server.join(timeout=4)
    output = result.stdout
    assert result.returncode == 0 and not failures and not server.is_alive(), (failures, output)
    sections = output.split("SNAPSHOT_START ")[1:]
    assert len(sections) == len(cases), output
    for section, (_, expected) in zip(sections, cases):
        records = [line.split("SNAPSHOT_RESULT ", 1)[1] for line in section.splitlines()
                   if "SNAPSHOT_RESULT " in line]
        assert len(records) == 1, section
        record = json.loads(records[0])
        assert record["pending"] is False, section
        if isinstance(expected, list):
            assert record["clients"] == expected and not record["reason"], section
            assert "PeerClosedError" not in section, section
        else:
            assert record["clients"] is None and record["reason"].startswith(expected), section
    print("PASS snapshot: fragmented UTF-8, reset, EOF errors, timeout recovery, early close")
