"""nix develop --command python3 tests/native/battery-state.py

Use the real Quickshell UPower adapter on a private bus. No host power action,
charger, system service, or desktop session is changed.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

source = Path(__file__).resolve().parents[2]
if len(sys.argv) == 1:
    with tempfile.TemporaryDirectory(prefix="battery-state-test-") as temporary:
        root = Path(temporary)
        shutil.copytree(source / "src/modules/common", root / "modules/common")
        shutil.copyfile(source / "tests/native/battery-state.qml", root / "shell.qml")
        (root / "runtime").mkdir(mode=0o700)
        (root / "proc/sys/kernel/random").mkdir(parents=True)
        (root / "proc/sys/kernel/random/boot_id").write_text("fixture-boot\n")
        config = root / "dbus.conf"
        config.write_text('''<busconfig><type>session</type><listen>unix:tmpdir=/tmp</listen>
<policy context="default"><allow own="*"/><allow send_destination="*"/>
<allow receive_sender="*"/></policy></busconfig>''')
        (root / "backend").write_text("#!" + shutil.which("bash") + '''
set -eu
printf '%s\\n' "${3:-}" >>"$TEST_BATTERY_STATE/samples"
if [ -e "$TEST_BATTERY_STATE/delay" ]; then
  rm "$TEST_BATTERY_STATE/delay"
  touch "$TEST_BATTERY_STATE/started"
  sleep 0.4
fi
exec bash "$TEST_SOURCE_ROOT/src/backend/desktop-shell.sh" "$@"
''')
        (root / "backend").chmod(0o700)
        sys.exit(subprocess.call(["dbus-run-session", "--config-file=" + str(config), "--",
                                  sys.executable, __file__, str(root)]))

root = Path(sys.argv[1])
os.environ["DBUS_SYSTEM_BUS_ADDRESS"] = os.environ["DBUS_SESSION_BUS_ADDRESS"]
DBusGMainLoop(set_as_default=True)
bus = dbus.SystemBus()
name = dbus.service.BusName("org.freedesktop.UPower", bus)
interface = "org.freedesktop.UPower"
device_path = "/org/freedesktop/UPower/devices/DisplayDevice"


class PowerObject(dbus.service.Object):
    def __init__(self, path, iface, values):
        super().__init__(bus, path)
        self.iface, self.values = iface, values

    @dbus.service.method("org.freedesktop.DBus.Properties", in_signature="s", out_signature="a{sv}")
    def GetAll(self, iface):
        return self.values if iface == self.iface else {}

    @dbus.service.signal("org.freedesktop.DBus.Properties", signature="sa{sv}as")
    def PropertiesChanged(self, iface, changed, invalidated):
        pass

    def update(self, key, value):
        self.values[key] = value
        self.PropertiesChanged(self.iface, {key: value}, [])


class Power(PowerObject):
    @dbus.service.method(interface, out_signature="ao")
    def EnumerateDevices(self):
        return []

    @dbus.service.method(interface, out_signature="o")
    def GetDisplayDevice(self):
        return device_path


power = Power("/org/freedesktop/UPower", interface, {"OnBattery": dbus.Boolean(True)})
device = PowerObject(device_path, interface + ".Device", {
    "Type": dbus.UInt32(2), "PowerSupply": dbus.Boolean(True),
    "IsPresent": dbus.Boolean(True), "State": dbus.UInt32(2),
    "Percentage": dbus.Double(80), "Energy": dbus.Double(40),
    "EnergyFull": dbus.Double(50), "EnergyRate": dbus.Double(6),
    "TimeToEmpty": dbus.Int64(24000), "TimeToFull": dbus.Int64(0),
    "Capacity": dbus.Double(100), "IconName": "battery-full-symbolic",
    "NativePath": "BAT0", "Model": "Fixture",
})
env = os.environ | {"QT_QPA_PLATFORM": "offscreen", "XDG_RUNTIME_DIR": str(root / "runtime"),
                    "DESKTOP_SHELL_BACKEND": str(root / "backend"), "TEST_BATTERY_STATE": str(root),
                    "TEST_SOURCE_ROOT": str(source), "XDG_STATE_HOME": str(root / "state"),
                    "DESKTOP_SHELL_PROC_ROOT": str(root / "proc"),
                    "DESKTOP_SHELL_SYS_ROOT": str(root / "no-sysfs")}
env.pop("WAYLAND_DISPLAY", None)
env.pop("DISPLAY", None)
log = (root / "quickshell.log").open("w")
process = subprocess.Popen(["quickshell", "--no-color", "--path", str(root / "shell.qml")],
                           env=env, stdout=log, stderr=subprocess.STDOUT)
loop = GLib.MainLoop()
step, deadline, failure, quiet_until, recorded_count = 0, time.monotonic() + 4, None, 0, 0


def ipc(method):
    return subprocess.run(["quickshell", "ipc", "--path", str(root / "shell.qml"),
                           "call", "fixture", method], env=env, capture_output=True, text=True, timeout=1)


def advance():
    global step, deadline, failure, quiet_until, recorded_count
    try:
        output = ipc("state")
        state = json.loads(output.stdout) if output.returncode == 0 else {}
        data = state.get("data", {})
        history = data.get("analysis", {})
        passed = [
            lambda: state.get("ready") and data.get("capacity") == 80 and history.get("bootWh") == 0,
            lambda: data.get("power") == "8.4W" and abs(history.get("bootWh", 0) - 0.1) < 1e-6,
            lambda: data.get("onBattery") is False and history.get("currentDraw") == "--",
            lambda: data.get("status") == "Charging",
            lambda: data.get("status") == "Full",
            lambda: data.get("capacity") == 81,
            lambda: data.get("available") is False,
            lambda: (root / "started").exists() and data.get("status") == "Discharging",
            lambda: data.get("status") == "Charging",
            lambda: data.get("status") == "Discharging" and data.get("capacity") == 82,
            lambda: abs(history.get("bootWh", 0) - 0.2) < 1e-6 and history.get("bootSeconds", 0) > 0,
            lambda: data.get("capacity") == 83 and state.get("lockData", {}).get("capacity") == 83
                    and time.monotonic() >= quiet_until,
        ][step]()
        if not passed:
            if time.monotonic() >= deadline:
                raise AssertionError(f"step {step} did not react within 2 seconds: {state}")
            return True
        if step == 0:
            device.update("Energy", dbus.Double(39.9))
            device.update("EnergyRate", dbus.Double(8.4))
        elif step == 1:
            power.update("OnBattery", dbus.Boolean(False))
        elif step == 2:
            device.update("State", dbus.UInt32(1))
        elif step == 3:
            device.update("State", dbus.UInt32(4))
        elif step == 4:
            device.update("Percentage", dbus.Double(81))
        elif step == 5:
            device.update("IsPresent", dbus.Boolean(False))
        elif step == 6:
            (root / "delay").touch()
            device.update("IsPresent", dbus.Boolean(True))
            power.update("OnBattery", dbus.Boolean(True))
            device.update("State", dbus.UInt32(2))
            device.update("Energy", dbus.Double(39.8))
        elif step == 7:
            power.update("OnBattery", dbus.Boolean(False))
            device.update("State", dbus.UInt32(1))
            device.update("Energy", dbus.Double(39.9))
        elif step == 8:
            power.update("OnBattery", dbus.Boolean(True))
            device.update("State", dbus.UInt32(2))
            device.update("Percentage", dbus.Double(82))
            device.update("Energy", dbus.Double(39.7))
        elif step == 9:
            device.update("Energy", dbus.Double(39.6))
        elif step == 10:
            assert ipc("stopRecording").returncode == 0
            recorded_count = len((root / "samples").read_text().splitlines())
            quiet_until = time.monotonic() + 0.2
            device.update("Percentage", dbus.Double(83))
        else:
            assert len((root / "samples").read_text().splitlines()) == recorded_count, "display-only model wrote history"
            samples = [json.loads(line) for line in (root / "samples").read_text().splitlines()]
            assert all("energyUwh" in entry for entry in samples)
            print("PASS native battery: live readings, AC, charging, removal, drain history, delayed transitions and lock ownership", flush=True)
            loop.quit()
            return False
        step += 1
        deadline = time.monotonic() + 2
        return True
    except Exception as error:
        failure = error
        loop.quit()
        return False


GLib.timeout_add(30, advance)
try:
    loop.run()
finally:
    process.terminate()
    process.wait(timeout=3)
    log.close()
if failure:
    print((root / "quickshell.log").read_text(), file=sys.stderr)
    raise failure
