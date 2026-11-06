import QtQuick
import Quickshell
import Quickshell.Io

Scope {
  id: root

  property string backend: Quickshell.env("DESKTOP_SHELL_BACKEND")
  property var sample: ({ available: false })
  property var data: ({})
  property var pendingSamples: []
  property var currentSample: ({})
  property double previousTime: 0

  function recordSample() {
    if (!sample.available && previousTime === 0)
      return;
    const now = Date.now() / 1000;
    const awakeSeconds = awakeClock.restart();
    // Sparse updates are valid. Sleep and wall-clock jumps break the baseline.
    const continuous = previousTime > 0 && now >= previousTime
      && Math.abs(now - previousTime - awakeSeconds) < 2;
    previousTime = now;
    pendingSamples = pendingSamples.concat([{
      now: now,
      continuous: continuous,
      status: sample.available && sample.onBattery ? sample.status : "External",
      energyUwh: sample.available ? Math.round(sample.energy * 1000000) : 0
    }]);
    submitNext();
  }

  function submitNext() {
    if (history.running || pendingSamples.length === 0)
      return;
    currentSample = pendingSamples[0];
    pendingSamples = pendingSamples.slice(1);
    history.running = true;
  }

  onSampleChanged: Qt.callLater(root.recordSample)
  Component.onCompleted: Qt.callLater(root.recordSample)

  // A monotonic stopwatch, with no periodic callbacks or wakeups.
  ElapsedTimer { id: awakeClock }

  Process {
    id: history
    command: [root.backend, "bar", "battery-analysis", JSON.stringify(root.currentSample)]
    onExited: function(code) {
      if (code !== 0)
        console.warn("battery: could not update drain history");
      Qt.callLater(root.submitNext);
    }
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const next = JSON.parse(text);
          if (next && typeof next.bootWh === "number")
            root.data = next;
        } catch (error) {
          console.warn("battery: invalid drain history: " + error);
        }
      }
    }
  }
}
