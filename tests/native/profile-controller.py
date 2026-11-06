"""Run in the dev shell: python3 tests/native/profile-controller.py."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

source = Path(__file__).resolve().parents[2] / "src/modules"
with tempfile.TemporaryDirectory(prefix="profile-controller-test-") as temporary:
    root = Path(temporary)
    common = root / "common"
    launcher = root / "launcher"
    common.mkdir()
    launcher.mkdir()
    # Keep the real controller and planning logic; replace only compositor I/O.
    # Removing the native imports ensures this test cannot touch the live session.
    controller = (source / "launcher/ProfileController.qml").read_text()
    controller = controller.replace("import Quickshell\n", "")
    controller = controller.replace("import Quickshell.Hyprland\n", "")
    controller = controller.replace("Scope {", "Item {", 1)
    (launcher / "ProfileController.qml").write_text(controller)
    for name in ["ProfileLogic.js", "LauncherSearch.js"]:
        (launcher / name).write_text((source / "launcher" / name).read_text())
    (common / "HyprlandWindow.js").write_text((source / "common/HyprlandWindow.js").read_text())
    (common / "qmldir").write_text("singleton Hyprland 1.0 Hyprland.qml\n")
    (common / "Hyprland.qml").write_text('''pragma Singleton
import QtQuick
QtObject {
  property var clients: []
  property var toplevels: ({values: clients})
  property var activeToplevel: null
  property var launches: []
  signal rawEvent(var event)
}
''')
    (common / "HyprlandClientSnapshot.qml").write_text('''import QtQuick
QtObject {
  signal succeeded(var clients)
  signal failed(string reason)
  function request() { Qt.callLater(() => succeeded(Hyprland.clients)); return true; }
}
''')
    (common / "HyprlandAdapter.qml").write_text('''import QtQuick
QtObject {
  function launchDesktopEntryInWorkspace(id, workspace) {
    Hyprland.launches = Hyprland.launches.concat([{id, workspace}]);
    return true;
  }
  function moveWindowToWorkspace(address, workspace) {
    Qt.callLater(function() {
      Hyprland.clients = Hyprland.clients.map(function(client) {
        return client.address === address ? Object.assign({}, client, {workspace: {id: workspace}}) : client;
      });
      Hyprland.rawEvent({name: "movewindowv2", data: address + "," + workspace + "," + workspace});
    });
  }
}
''')
    (root / "tst_controller.qml").write_text('''import QtQuick
import QtTest
import "launcher"
import "common"
TestCase {
  name: "ProfileController"
  ProfileController {
    id: controller
    applications: [{id: "example", startupClass: "example"}, {id: "other", startupClass: "other"}]
    profiles: ({a: {applications: [{id: "example.desktop", workspace: 1}]},
                b: {applications: [{id: "example.desktop", workspace: 4}, {id: "other.desktop", workspace: 5}]},
                c: {applications: [{id: "example.desktop", workspace: 6}]}})
    presentationWindows: Hyprland.clients
  }
  SignalSpy { id: finished; target: controller; signalName: "applyFinished" }
  function init() {
    Hyprland.clients = [];
    Hyprland.launches = [];
    controller.launchLeases = ({});
    controller.lastApplyResults = ({});
    finished.clear();
  }
  function startSwitch() {
    verify(controller.applyProfile("a"));
    tryCompare(finished, "count", 1);
    compare(Hyprland.launches.length, 1);
    verify(controller.applyProfile("b"));
    wait(350);
    compare(controller.activeProfileId, "b");
    compare(finished.count, 1);
    compare(Hyprland.launches.length, 1);
  }
  function test_switch_places_delayed_window_and_preserves_queued_profile() {
    startSwitch();
    verify(controller.applyProfile("c"));
    Hyprland.clients = [{address: "0x2", class: "example", workspace: {id: 1}}];
    tryCompare(finished, "count", 3);
    compare(finished.signalArguments[1][0], "b");
    verify(finished.signalArguments[1][1]);
    verify(finished.signalArguments[2][1]);
    compare(Hyprland.clients[0].workspace.id, 6);
    compare(Hyprland.launches.length, 2);
    compare(Hyprland.launches[1].id, "other.desktop");
    compare(controller.activeProfileId, "");
  }
  function test_wait_expires_without_relaunching() {
    startSwitch();
    // Advance the captured deadline instead of sleeping for the full lease.
    controller.launchWaitDeadline = Date.now() - 1;
    tryCompare(finished, "count", 2);
    verify(!finished.signalArguments[1][1]);
    compare(controller.activeProfileId, "");
    compare(Hyprland.launches.length, 1);
  }
}
''')
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen")
    runner = Path(shutil.which("qmltestrunner")).resolve()
    subprocess.run([str(runner), "-import", str(runner.parent.parent / "lib/qt-6/qml"),
                    "-input", str(root / "tst_controller.qml")], env=env, check=True)
