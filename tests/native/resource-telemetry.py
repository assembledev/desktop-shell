"""Exercise real asynchronous procfs reads and independent GPU process lifetime."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

source = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[2]
quickshell = shutil.which("quickshell")
assert quickshell, "quickshell is required"
with tempfile.TemporaryDirectory(prefix="resource-telemetry-") as directory:
    root = Path(directory)
    for name in ["home", "runtime", "config", "cache", "state", "data"]:
        (root / name).mkdir(mode=0o700)
    (root / "modules/bar").mkdir(parents=True)
    for name in ["RamState.qml", "RamStatus.js", "VramState.qml"]:
        shutil.copy(source / "src/modules/bar" / name, root / "modules/bar" / name)
    shutil.copy(source / "tests/native/resource-telemetry.qml", root / "shell.qml")
    backend = root / "gpu"
    backend.write_text(
        f"#!{sys.executable}\n"
        + """import json, os, pathlib, sys, time
root = pathlib.Path(os.environ["GPU_FIXTURE_ROOT"])
assert sys.argv[1:] == ["bar", "vram-json"]
with (root/"calls").open("a") as f: f.write("call\\n")
time.sleep(float((root/"delay").read_text()))
print((root/"gpu-data").read_text())
"""
    )
    backend.chmod(0o700)
    (root / "delay").write_text("0.7")
    (root / "gpu-data").write_text('{"hasVram":true,"vram":0.25,"vramText":"1.0/4G"}')

    def memory(available):
        temporary = root / "meminfo.tmp"
        temporary.write_text(f"MemTotal: 8388608 kB\nMemAvailable: {available} kB\n")
        temporary.replace(root / "meminfo")

    memory(4194304)
    env = {
        "PATH": os.environ["PATH"],
        "LANG": "C.UTF-8",
        "QT_QPA_PLATFORM": "offscreen",
        "HOME": str(root / "home"),
        "XDG_RUNTIME_DIR": str(root / "runtime"),
        "DBUS_SESSION_BUS_ADDRESS": "unix:path=" + str(root / "no-bus"),
        "DBUS_SYSTEM_BUS_ADDRESS": "unix:path=" + str(root / "no-bus"),
        "RAM_FIXTURE": str(root / "meminfo"),
        "GPU_FIXTURE": str(backend),
        "GPU_FIXTURE_ROOT": str(root),
    }
    env.update(
        {
            "XDG_" + n + "_HOME": str(root / n.lower())
            for n in ["CONFIG", "CACHE", "STATE", "DATA"]
        }
    )

    def ipc(method, *args):
        return subprocess.check_output(
            [
                quickshell,
                "ipc",
                "--path",
                str(root / "shell.qml"),
                "call",
                "test",
                method,
                *args,
            ],
            env=env,
            text=True,
            stderr=subprocess.PIPE,
            timeout=3,
        ).strip()

    def snapshot():
        return json.loads(ipc("snapshot"))

    def wait_for(predicate, description):
        deadline = time.monotonic() + 4
        while time.monotonic() < deadline:
            try:
                if predicate():
                    return
            except (subprocess.CalledProcessError, json.JSONDecodeError):
                pass
            time.sleep(0.025)
        raise AssertionError(description)

    def calls():
        return (
            len((root / "calls").read_text().splitlines())
            if (root / "calls").exists()
            else 0
        )

    with (root / "shell.log").open("w") as log:
        shell = subprocess.Popen(
            [quickshell, "--no-color", "--path", str(root / "shell.qml")],
            env=env,
            stdout=log,
            stderr=log,
        )
        try:
            wait_for(
                lambda: snapshot()["real"], "real zero-sized procfs file was not loaded"
            )
            assert not snapshot()["ram"]["available"] and calls() == 0
            ipc("activate", "true", "true")
            wait_for(
                lambda: snapshot()["ram"]["ramText"] == "4.0/8G" and calls() == 1,
                "opening did not sample immediately",
            )
            memory(2097152)
            wait_for(
                lambda: snapshot()["ram"]["ramText"] == "6.0/8G",
                "RAM failed to refresh while GPU blocked",
            )
            assert calls() == 1 and not snapshot()["gpu"]["hasVram"], (
                "overlapping GPU collectors"
            )
            wait_for(
                lambda: snapshot()["gpu"]["hasVram"],
                "GPU result was not published independently",
            )
            ipc("activate", "false", "false")
            stopped = calls()
            memory(6291456)
            ipc("refresh")
            time.sleep(0.35)
            assert (
                calls() == stopped
                and not snapshot()["ram"]["available"]
                and not snapshot()["gpu"]["hasVram"]
            )
            (root / "delay").write_text("0")
            ipc("activate", "true", "false")
            wait_for(
                lambda: snapshot()["ram"]["ramText"] == "2.0/8G",
                "reopening did not refresh RAM",
            )
            time.sleep(0.2)
            assert calls() == stopped, "disabled VRAM still spawned a collector"
            (root / "meminfo").write_text("invalid")
            wait_for(
                lambda: not snapshot()["ram"]["available"],
                "invalid data retained a plausible stale value",
            )
            memory(4194304)
            wait_for(
                lambda: snapshot()["ram"]["available"],
                "memory reader failed to recover",
            )
            (root / "gpu-data").write_text("not-json")
            ipc("activate", "true", "true")
            wait_for(lambda: calls() > stopped, "GPU did not restart")
            time.sleep(0.15)
            assert not snapshot()["gpu"]["hasVram"], (
                "malformed GPU result retained old data"
            )
            # A rapid hide/show reuses the one bounded in-flight GPU query.
            ipc("activate", "true", "false")
            time.sleep(0.2)
            (root / "delay").write_text("0.6")
            (root / "gpu-data").write_text(
                '{"hasVram":true,"vram":0.25,"vramText":"1.0/4G"}'
            )
            baseline = calls()
            ipc("activate", "true", "true")
            wait_for(lambda: calls() > baseline, "slow GPU query did not start")
            ipc("activate", "true", "false")
            ipc("activate", "true", "true")
            time.sleep(0.15)
            assert calls() == baseline + 1, (
                "rapid reopen duplicated the in-flight GPU query"
            )
            wait_for(
                lambda: snapshot()["gpu"]["hasVram"], "reused GPU query lost its result"
            )
            errors = [
                line
                for line in (root / "shell.log").read_text().splitlines()
                if any(
                    e in line
                    for e in [
                        "TypeError",
                        "ReferenceError",
                        "Binding loop",
                        "Unable to assign",
                    ]
                )
            ]
            assert not errors, "\n".join(errors)
            print(
                "PASS resource telemetry: real procfs, visibility, refresh, GPU isolation, cancellation, recovery"
            )
        except Exception:
            print((root / "shell.log").read_text())
            raise
        finally:
            shell.terminate()
            try:
                shell.wait(timeout=3)
            except subprocess.TimeoutExpired:
                shell.kill()
                shell.wait()
