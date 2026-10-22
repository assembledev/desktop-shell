import QtQuick
import Quickshell
import Quickshell.Io
import "modules/tailscale"

ShellRoot {
  id: suite
  property int step: 0
  property int ticks: 0
  property int receivedBatches: 0
  property var receivedFiles: []
  Connections { target: model; function onFilesReceived(files) { suite.receivedBatches++; suite.receivedFiles = files; } }
  TailscaleModel { id: model; enabled: true }
  function verify(condition, message) {
    if (!condition) { console.error("FAIL tailscale model: " + message); Qt.exit(1); }
  }
  Process {
    id: scenario
    onExited: function(code) { suite.verify(code === 0, "fixture scenario failed"); model.refresh(); }
  }
  Timer {
    interval: 50; running: true; repeat: true
    onTriggered: {
      suite.ticks++;
      if (suite.step === 0 && model.connected && model.data.peers.length === 2 && model.data.inboxAvailable === true) {
        suite.verify(suite.receivedBatches === 0, "startup backlog was announced");
        model.detailsActive = true;
        model.selectedId = "a";
        suite.step = 1;
        suite.ticks = 0;
      } else if (suite.step === 1 && suite.ticks === 2) {
        // A's delayed direct result must never be shown for B.
        model.selectedId = "b";
        suite.step = 2;
      } else if (suite.step === 2 && model.hasProbe) {
        suite.verify(model.probe.peerId === "b", "late result assigned to another device");
        suite.verify(model.connectionText === "Peer relay", "peer relay collapsed into direct or DERP");
        suite.verify(model.pingText === "22 ms", "wrong latency");
        suite.verify(model.canSend, "eligible peer missing send action");
        scenario.exec([model.backend, "scenario", "changed"]);
        suite.step = 3;
      } else if (suite.step === 3 && model.selected?.addresses[0] === "100.64.0.9" && model.data.files.length === 1) {
        suite.verify(!model.canSend, "eligibility did not refresh");
        suite.verify(model.offline.length === 1, "online status did not refresh");
        suite.verify(model.data.files.length === 1, "inbox did not refresh");
        suite.verify(suite.receivedBatches === 1 && suite.receivedFiles[0].name === "fixture.txt", "new inbox file did not produce exactly one notification");
        model.selectedId = "a";
        suite.verify(model.connectionText === "Offline" && model.pingText === "—", "offline peer retains route/latency");
        scenario.exec([model.backend, "scenario", "broken"]);
        suite.step = 4;
      } else if (suite.step === 4 && model.data.inboxAvailable === false) {
        suite.verify(model.data.files.length === 1 && suite.receivedBatches === 1, "failed read lost inbox or repeated notification");
        scenario.exec([model.backend, "scenario", "changed"]);
        suite.step = 5;
      } else if (suite.step === 5 && model.data.inboxAvailable === true) {
        suite.verify(suite.receivedBatches === 1, "reconnect announced an existing file");
        scenario.exec([model.backend, "scenario", "removed"]);
        suite.step = 6;
      } else if (suite.step === 6 && model.selected === null && model.data.files.length === 0) {
        suite.verify(!model.canSend && !model.hasProbe, "removed peer retains actions or probe");
        suite.verify(model.data.files.length === 0, "empty inbox retains files");
        model.observedAt = Date.now() - 10000;
        suite.verify(!model.fresh && !model.canSend, "stale sample retains send eligibility");
        model.detailsActive = false;
        suite.verify(model.probe === null, "close retains a probe");
        suite.step = 7;
        suite.ticks = 0;
      } else if (suite.step === 7 && suite.ticks >= 8) {
        scenario.exec([model.backend, "scenario", "short-wait"]);
        suite.step = 8;
        suite.ticks = 0;
      } else if (suite.step === 8 && suite.ticks >= 12) {
        scenario.exec([model.backend, "scenario", "removed"]);
        suite.step = 9;
        suite.ticks = 0;
      } else if (suite.step === 9 && suite.ticks >= 50) {
        model.enabled = false;
        suite.step = 10;
        suite.ticks = 0;
      } else if (suite.step === 10 && suite.ticks >= 6) {
        suite.verify(suite.receivedBatches === 1, "empty waits repeated a notification");
        console.log("PASS tailscale model: peer refresh, first arrival via blocking wait, dedup, failure recovery, empty response throttling and cancellation");
        Qt.quit();
      }
    }
  }
  Timer { interval: 20000; running: true; onTriggered: { console.error("FAIL tailscale model: timeout at step " + suite.step); Qt.exit(1); } }
}
