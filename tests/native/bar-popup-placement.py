"""Run with quickshell and sway on PATH; uses a private headless compositor."""

import os
import shutil
import subprocess
import tempfile
import time
from pathlib import Path

src = Path(__file__).resolve().parents[2]
qs = shutil.which("quickshell")
assert qs, "quickshell is required"
sway = shutil.which("sway")
assert sway, "sway is required"
with tempfile.TemporaryDirectory(prefix="popup-headless-") as tmp:
    r = Path(tmp)
    for d in ("home", "runtime", "config", "cache", "state", "data"):
        (r / d).mkdir(mode=0o700)
    env = {
        "PATH": os.environ["PATH"],
        "LANG": "C.UTF-8",
        "QT_QPA_PLATFORM": "wayland",
        "QT_QUICK_BACKEND": "software",
        "HOME": str(r / "home"),
        "XDG_RUNTIME_DIR": str(r / "runtime"),
        "DBUS_SESSION_BUS_ADDRESS": "unix:path=" + str(r / "no-bus"),
        "DBUS_SYSTEM_BUS_ADDRESS": "unix:path=" + str(r / "no-bus"),
        "DESKTOP_SHELL_BACKEND": shutil.which("true"),
        "WLR_BACKENDS": "headless",
        "WLR_HEADLESS_OUTPUTS": "2",
        "WLR_RENDERER": "pixman",
        "WLR_LIBINPUT_NO_DEVICES": "1",
        "XKB_DEFAULT_LAYOUT": "us",
    }
    env.update(
        {
            "XDG_" + n + "_HOME": str(r / n.lower())
            for n in ["CONFIG", "CACHE", "STATE", "DATA"]
        }
    )
    (r / "sway.conf").write_text(
        "output HEADLESS-1 resolution 1200x800 scale 1\n"
        "output HEADLESS-2 resolution 900x1600 scale 1.5\n"
        "xwayland disable\n"
    )
    with open(r / "compositor.log", "w") as log:
        compositor = subprocess.Popen(
            [sway, "--config", str(r / "sway.conf")],
            env=env,
            stdout=log,
            stderr=subprocess.STDOUT,
        )
        try:
            for _ in range(50):
                sockets = [
                    p for p in (r / "runtime").glob("wayland-*") if p.is_socket()
                ]
                if sockets:
                    break
                assert compositor.poll() is None, Path(log.name).read_text()
                time.sleep(0.1)
            assert sockets, "compositor startup timed out"
            env["WAYLAND_DISPLAY"] = sockets[0].name
            shutil.copytree(src / "src/modules", r / "modules")
            shutil.copy(src / "tests/native/network-popover-focus.qml", r / "shell.qml")
            p = subprocess.run(
                [qs, "--no-color", "--path", str(r / "shell.qml")],
                env=env,
                capture_output=True,
                text=True,
                timeout=15,
            )
            output = p.stdout + p.stderr
            assert p.returncode == 0 and "PASS network popover" in output, output
            print(
                "PASS native Wayland network pointer/keyboard opening and repeated toggle"
            )
            shell = (src / "src/shell.qml").read_text()
            insertion = """
  property int checkStep: 0
  function check(condition, message) {
    if (!condition) { console.error("FAIL placement smoke:", message); Qt.exit(1); }
  }
  Timer {
    running: true; repeat: true; interval: 120
    onTriggered: {
      const screenIndex = Math.floor(root.checkStep / 5);
      const step = root.checkStep % 5;
      const screen = shellConfig.screens[screenIndex];
      const bar = root.barFor(screen);
      root.check(bar !== null, "missing bar");
      root.check(shellConfig.screens.some(s => s.name === "HEADLESS-2" && s.width === 600 && s.height > s.width), "portrait fractional scaling missing");
      if (step === 0) {
        root.check(barState.metricsVisible, "visible landscape consumer did not enable shared RAM");
        root.check(bar.metricsVisible === !bar.portraitMode, "portrait bar enabled hidden resource metrics");
        root.check(bar.surface.popupTrigger("network") !== null, "missing network anchor");
        networkDetails.openDetails(screen, bar.surface.popupTrigger("network"));
      } else if (step === 1) {
        root.check(networkDetails.open, "network closed unexpectedly");
        calendar.openCalendar(screen, bar.surface.popupTrigger("calendar"));
      } else if (step === 2) {
        root.check(calendar.open && !networkDetails.open, "task switch failed");
        bar.power("open", true);
      } else if (step === 3) {
        root.check(bar.powerMenuOpen && !calendar.open, "power task failed");
        bar.power("close");
        calendar.openCalendar(screen);
      } else if (step === 4) {
        root.check(calendar.open && calendar.popupAnchor !== null, "fallback control anchor missing");
        barState.barOpen = false;
        root.check(!calendar.open, "concealed bar kept calendar open");
        root.check(!barState.metricsVisible && !barState.vramVisible, "hidden bars kept resource collectors enabled");
        if (screenIndex + 1 === shellConfig.screens.length) {
          root.check(shellConfig.screens.length === 2, "missing mixed-scale output");
          console.log("PASS full shell placement smoke"); Qt.quit();
        } else barState.barOpen = true;
      }
      root.checkStep++;
    }
  }
"""
            shell = shell[: shell.rfind("}")] + insertion + "}\n"
            (r / "shell.qml").write_text(shell)
            p = subprocess.run(
                [qs, "--no-color", "--path", str(r / "shell.qml")],
                env=env,
                capture_output=True,
                text=True,
                timeout=15,
            )
            output = p.stdout + p.stderr
            assert p.returncode == 0 and "PASS full shell placement smoke" in output, (
                output
            )
            errors = [
                line
                for line in output.splitlines()
                if any(
                    s in line
                    for s in [
                        "TypeError",
                        "ReferenceError",
                        "Binding loop",
                        "Unable to assign",
                        "FAIL",
                    ]
                )
            ]
            assert not errors, "\n".join(errors)
            print(
                "PASS full shell native Wayland: real bar anchors, network/calendar/power switching, keyboard fallback"
            )
        finally:
            compositor.terminate()
            try:
                compositor.wait(timeout=3)
            except subprocess.TimeoutExpired:
                compositor.kill()
                compositor.wait()
