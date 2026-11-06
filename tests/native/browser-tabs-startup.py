"""Exercise the real launcher FileView and native host through CLI startup."""
import json
import os
from pathlib import Path
import queue
import select
import struct
import subprocess
import sys
import tempfile
import threading
import time

source = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[2]
launcher = (source / "src/modules/launcher/LauncherView.qml").read_text()
start = launcher.index("  FileView {\n    id: browserTabsFile")
file_view = launcher[start:launcher.index("\n  }", start) + 4]

with tempfile.TemporaryDirectory(prefix="browser-tabs-startup-") as temporary:
    root = Path(temporary)
    for name in ["home", "runtime", "config", "cache", "state", "data"]:
        (root / name).mkdir(mode=0o700)
    (root / "config.json").write_text('{"browserTabs":{"enable":true}}')
    (root / "shell.qml").write_text('''import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {
  id: root
  property string browserTabsPath: Quickshell.env("XDG_RUNTIME_DIR") + "/desktop-shell/browser-tabs.json"
  function loadBrowserTabs(raw) {
    const state = JSON.parse(raw);
    console.log("TAB_IDS", JSON.stringify(state.tabs.map(tab => tab.tabId)));
  }
  function clearBrowserTabs() { console.log("TABS_DISCONNECTED"); }
''' + file_view + "\n}\n")
    env = {"PATH": os.environ["PATH"], "LANG": "C.UTF-8", "QT_QPA_PLATFORM": "offscreen",
           "HOME": str(root / "home"), "XDG_RUNTIME_DIR": str(root / "runtime"),
           "DESKTOP_SHELL_CONFIG": str(root / "config.json"), "DESKTOP_SHELL_QML": str(root),
           "DBUS_SESSION_BUS_ADDRESS": "unix:path=" + str(root / "no-bus"),
           "DBUS_SYSTEM_BUS_ADDRESS": "unix:path=" + str(root / "no-bus")}
    env.update({"XDG_" + name + "_HOME": str(root / name.lower())
                for name in ["CONFIG", "CACHE", "STATE", "DATA"]})
    processes = []
    threads = []

    def launch(argv):
        process = subprocess.Popen(argv, env=env, stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        processes.append(process)
        return process

    def start_shell():
        process = launch(["bash", str(source / "src/backend/desktop-shell.sh"), "run"])
        events, output = queue.Queue(), []

        def read_output():
            for raw in process.stdout:
                line = raw.decode(errors="replace")
                output.append(line)
                events.put(line)

        thread = threading.Thread(target=read_output, daemon=True)
        thread.start()
        threads.append(thread)

        def expect(marker):
            deadline = time.monotonic() + 5
            while True:
                try:
                    line = events.get(timeout=max(0, deadline - time.monotonic()))
                except queue.Empty:
                    raise AssertionError(f"missing {marker}:\n{''.join(output)}") from None
                if marker in line:
                    return

        return process, expect

    def start_host():
        host = launch([sys.executable, str(source / "browser-extension/native-host.py")])
        assert select.select([host.stdout], [], [], 5)[0], "native host never became ready"
        length = struct.unpack("@I", host.stdout.read(4))[0]
        assert length < 1024, "unexpected native host output"
        assert json.loads(host.stdout.read(length)) == {"type": "ready"}
        return host

    def publish(host, tab_id):
        payload = json.dumps({"type": "snapshot", "tabs": [{"tabId": tab_id}]}).encode()
        host.stdin.write(struct.pack("@I", len(payload)) + payload)
        host.stdin.flush()

    def stop_host(host):
        host.stdin.close()
        assert host.wait(timeout=3) == 0

    try:
        # The shell starts first on a fresh login. No device/desktop service is used.
        shell, expect = start_shell()
        expect("TABS_DISCONNECTED")
        host = start_host()
        publish(host, 1)
        expect("TAB_IDS [1]")
        runtime = root / "runtime/desktop-shell"
        assert runtime.stat().st_mode & 0o777 == 0o700
        publish(host, 2)
        expect("TAB_IDS [2]")  # The host atomically replaces its snapshot.
        stop_host(host)
        expect("TABS_DISCONNECTED")
        host = start_host()
        publish(host, 3)
        expect("TAB_IDS [3]")  # Reconnect without restarting the shell.
        shell.terminate()
        shell.wait(timeout=3)
        shell, expect = start_shell()
        expect("TAB_IDS [3]")  # Browser-first startup preserves the live bridge.
        stop_host(host)
        expect("TABS_DISCONNECTED")
    finally:
        for process in processes:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
        for thread in threads:
            thread.join(timeout=1)
    print("PASS browser tabs: shell-first startup, atomic updates, disconnect/reconnect, browser-first startup")
