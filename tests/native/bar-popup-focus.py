"""Exercise popup input in a temporary nested Hyprland window.

Requires Hyprland, hyprctl, quickshell, wtype, cc, pkg-config, wayland-scanner
and Wayland client development files. Set WLR_VIRTUAL_POINTER_XML to the
wlr-virtual-pointer-unstable-v1.xml protocol file. Requires a Hyprland parent. All injected input and IPC target the private child compositor.
"""

import json
import os
from pathlib import Path
import select
import shlex
import shutil
import subprocess
import tempfile
import time

source = Path(__file__).resolve().parents[2]
names = [
    "Hyprland",
    "hyprctl",
    "quickshell",
    "wtype",
    "cc",
    "pkg-config",
    "wayland-scanner",
]
bins = {name: shutil.which(name) for name in names}
assert all(bins.values()), "Missing test executables: " + str(
    [n for n in names if not bins[n]]
)
parent_runtime = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
parent_display = os.environ["WAYLAND_DISPLAY"]
with tempfile.TemporaryDirectory(prefix="hy-") as directory:
    root = Path(directory)
    for name in ["home", "runtime", "config", "cache", "state", "data"]:
        (root / name).mkdir(mode=0o700)
    env = {
        "PATH": os.environ["PATH"],
        "HOME": str(root / "home"),
        "XDG_RUNTIME_DIR": str(root / "runtime"),
        "WAYLAND_DISPLAY": str(parent_runtime / parent_display),
        "DBUS_SESSION_BUS_ADDRESS": "unix:path=" + str(root / "no-bus"),
        "DBUS_SYSTEM_BUS_ADDRESS": "unix:path=" + str(root / "no-bus"),
        "AQ_DRM_DEVICES": "/dev/null",
        "LIBSEAT_BACKEND": "logind",
        "HYPRLAND_NO_SD_VARS": "1",
        "HYPRLAND_NO_SD_NOTIFY": "1",
        "LANG": "C.UTF-8",
        "QT_QPA_PLATFORM": "wayland",
        "QT_QUICK_BACKEND": "software",
    }
    env.update(
        {
            "XDG_" + n + "_HOME": str(root / n.lower())
            for n in ["CONFIG", "CACHE", "STATE", "DATA"]
        }
    )
    (root / "hyprland.lua").write_text(
        'hl.monitor({output="",mode="1280x800@60",position="2560x0",scale=1})\n'
        'hl.monitor({output="focus-primary",mode="1280x800@60",position="0x0",scale=1})\n'
        'hl.monitor({output="focus-test",mode="1280x800@60",position="1280x0",scale=1})\n'
        "hl.config({misc={disable_hyprland_logo=true,disable_splash_rendering=true},"
        "animations={enabled=false},debug={disable_logs=false,enable_stdout_logs=true}})\n"
    )
    shutil.copytree(source / "src/modules", root / "modules")
    shutil.copy(source / "tests/native/bar-popup-focus.qml", root / "shell.qml")
    protocol = os.environ["WLR_VIRTUAL_POINTER_XML"]
    for mode, name in [
        ("client-header", "virtual-pointer.h"),
        ("private-code", "virtual-pointer.c"),
    ]:
        subprocess.run(
            [bins["wayland-scanner"], mode, protocol, str(root / name)], check=True
        )
    flags = subprocess.check_output(
        [bins["pkg-config"], "--cflags", "--libs", "wayland-client"], text=True
    )
    subprocess.run(
        [
            bins["cc"],
            "-Wall",
            "-Wextra",
            "-Werror",
            "-I" + str(root),
            str(source / "tests/native/popup-pointer.c"),
            str(root / "virtual-pointer.c"),
            *shlex.split(flags),
            "-o",
            str(root / "pointer"),
        ],
        check=True,
    )
    processes = []

    def run(name, *args):
        result = subprocess.run(
            [bins[name], *args], env=env, capture_output=True, text=True, timeout=5
        )
        assert result.returncode == 0, result.stdout + result.stderr
        return result.stdout.strip()

    def eventually(predicate, description):
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            if predicate():
                return
            time.sleep(0.05)
        raise AssertionError(description)

    def ipc(method, *args):
        return run(
            "quickshell",
            "ipc",
            "--path",
            str(root / "shell.qml"),
            "call",
            "test",
            method,
            *args,
        )

    def snapshot():
        return json.loads(ipc("snapshot"))

    def move(x, y):
        run(
            "hyprctl",
            "eval",
            f"return hl.dispatch(hl.dsp.cursor.move({{x={x}, y={y}}}))",
        )
        pointer_command("move")

    def pointer_command(command):
        pointer.stdin.write(command + "\n")
        pointer.stdin.flush()
        assert select.select([pointer.stdout], [], [], 3)[0], (
            "pointer command timed out"
        )
        assert pointer.stdout.readline().strip() == "ok"

    def click():
        pointer_command("click")

    try:
        with open(root / "compositor.log", "w") as log:
            compositor = subprocess.Popen(
                [bins["Hyprland"], "--config", str(root / "hyprland.lua")],
                env=env,
                stdout=log,
                stderr=log,
            )
            processes.append(compositor)
            eventually(
                lambda: any(
                    p.is_socket() for p in (root / "runtime").glob("wayland-*")
                ),
                "nested compositor unavailable",
            )
            env["WAYLAND_DISPLAY"] = next(
                p.name for p in (root / "runtime").glob("wayland-*") if p.is_socket()
            )
            env["HYPRLAND_INSTANCE_SIGNATURE"] = next(
                (root / "runtime/hypr").iterdir()
            ).name
            run("hyprctl", "output", "create", "headless", "focus-primary")
            run("hyprctl", "output", "create", "headless", "focus-test")
            eventually(
                lambda: (
                    len(
                        [
                            m
                            for m in json.loads(run("hyprctl", "-j", "monitors"))
                            if m["name"].startswith("focus-")
                        ]
                    )
                    == 2
                ),
                "second output missing",
            )
            # Detach the temporary parent window once the isolated outputs exist.
            # Real parent input must not interfere with this test's virtual devices.
            run("hyprctl", "output", "remove", "WAYLAND-1")
            pointer = subprocess.Popen(
                [str(root / "pointer")],
                env=env,
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                text=True,
            )
            processes.append(pointer)
            assert select.select([pointer.stdout], [], [], 3)[0], (
                "pointer initialization timed out"
            )
            assert pointer.stdout.readline().strip() == "ready"
            monitors = json.loads(run("hyprctl", "-j", "monitors"))
            primary = next(m for m in monitors if m["name"] == "focus-primary")
            secondary = next(m for m in monitors if m["name"] == "focus-test")
            with open(root / "shell.log", "w") as shell_log:
                shell = subprocess.Popen(
                    [
                        bins["quickshell"],
                        "--no-color",
                        "--path",
                        str(root / "shell.qml"),
                    ],
                    env=env,
                    stdout=shell_log,
                    stderr=shell_log,
                )
                processes.append(shell)
                time.sleep(0.6)
                assert shell.poll() is None, (root / "shell.log").read_text()
                move(primary["x"] + 120, primary["y"] + 15)

                eventually(lambda: snapshot()["hover"], "bar trigger never hovered")
                for count in range(1, 5):
                    click()
                    eventually(
                        lambda: snapshot()["clicks"] == count,
                        "stationary trigger lost pointer ownership",
                    )
                    assert snapshot()["opened"] == (count % 2 == 1)
                    assert not snapshot()["grab"]
                ipc("open", "true")
                eventually(
                    lambda: snapshot()["grab"],
                    "keyboard opening never acquired native grab",
                )
                eventually(
                    lambda: snapshot()["active"],
                    "popup window never received keyboard focus",
                )
                run("wtype", "a")
                eventually(
                    lambda: snapshot()["text"] == "a", "popup did not receive keys"
                )
                move(
                    primary["x"] + primary["width"] - 20,
                    primary["y"] + primary["height"] - 20,
                )
                run("wtype", "b")
                eventually(
                    lambda: snapshot()["text"] == "ab",
                    "moving outside stole keyboard focus",
                )
                click()
                eventually(
                    lambda: not snapshot()["opened"], "outside click did not dismiss"
                )
                ipc("retain", "true")
                ipc("open", "true")
                eventually(
                    lambda: snapshot()["grab"], "reopening did not acquire focus"
                )
                ipc("close")
                eventually(
                    lambda: not snapshot()["grab"],
                    "closing retained input during fade-out",
                )
                ipc("open", "true")
                eventually(lambda: snapshot()["grab"], "rapid reopen failed")
                eventually(
                    lambda: snapshot()["active"], "popup keyboard focus not restored"
                )
                run("wtype", "c")
                eventually(
                    lambda: snapshot()["text"] == "abc",
                    "rapid reopen lost keyboard target",
                )
                ipc("suspend", "true")
                eventually(
                    lambda: not snapshot()["grab"], "chooser did not release grab"
                )
                eventually(
                    lambda: snapshot()["chooserActive"],
                    "chooser keyboard focus unavailable",
                )
                run("wtype", "d")
                eventually(
                    lambda: snapshot()["chooserText"] == "d",
                    "chooser could not receive keys",
                )
                ipc("suspend", "false")
                eventually(
                    lambda: snapshot()["grab"], "chooser return did not restore grab"
                )
                eventually(
                    lambda: snapshot()["active"], "popup keyboard focus not restored"
                )
                run("wtype", "e")
                eventually(
                    lambda: snapshot()["text"] == "abce",
                    "chooser return lost keyboard focus",
                )
                move(secondary["x"] + 120, secondary["y"] + 15)
                click()
                eventually(
                    lambda: snapshot()["other"] == 1, "other-output bar was blocked"
                )
                assert snapshot()["opened"], "allowlisted bar dismissed the popup"
                move(
                    secondary["x"] + secondary["width"] - 20,
                    secondary["y"] + secondary["height"] - 20,
                )
                click()
                eventually(
                    lambda: not snapshot()["opened"],
                    "outside click on second output did not dismiss",
                )
                move(primary["x"] + 120, primary["y"] + 15)
                ipc("open", "false")
                assert not snapshot()["grab"], (
                    "pointer open grabbed before entering card"
                )
                move(primary["x"] + 150, primary["y"] + 90)
                eventually(
                    lambda: snapshot()["grab"], "entering card did not acquire focus"
                )
                eventually(
                    lambda: snapshot()["active"], "popup keyboard focus not restored"
                )
                run("wtype", "f")
                eventually(
                    lambda: snapshot()["text"] == "abcef",
                    "pointer entry lost keyboard focus",
                )
                run("wtype", "-k", "Escape")
                eventually(lambda: not snapshot()["opened"], "Escape did not dismiss")
                assert snapshot()["appText"] == "", (
                    "popup keys leaked to the application"
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
                    "PASS native popup focus: stationary trigger, typing, outside dismissal, retained-surface reopen, chooser handoff, two outputs, pointer entry, Escape"
                )
    except Exception:
        if "shell" in locals() and shell.poll() is None:
            print("STATE", snapshot())
        for name in ["shell.log", "compositor.log"]:
            if (root / name).exists():
                print((root / name).read_text()[-4000:])
        raise
    finally:
        for process in reversed(processes):
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
