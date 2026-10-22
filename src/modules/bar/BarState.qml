import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import "../common"
import "../network"

Scope {
  id: root

  property string backend: Quickshell.env("DESKTOP_SHELL_BACKEND")
  property string stateDir: Quickshell.env("CONTROL_CENTER_STATE_DIR")
  property string preferencesDir: Quickshell.env("DESKTOP_SHELL_PREFERENCES_DIR")
  property var metrics: ({ ramText: "--", hasVram: false, vramText: "--" })
  property var notificationStatus: ({ text: "", class: "normal", tooltip: "Control center" })
  property bool notificationUnread: false
  property bool dnd: false
  property bool recording: false
  property double recordingStartedAt: 0
  property string recordingElapsed: "00:00"
  property bool barOpen: true
  readonly property var clockState: clock
  readonly property var batteryState: batterySampler
  readonly property var keyboardState: keyboardSampler
  readonly property var network: networkState
  readonly property var connection: connectionState
  readonly property var microphoneLinks: Pipewire.linkGroups.values.filter(link => Boolean(link.source?.audio && !link.source.isStream && !link.source.isSink))
  signal powerRequested(string action)

  NetworkState {
    id: networkState
    backend: root.backend
    configPath: Quickshell.env("DESKTOP_SHELL_NETWORK_CONTROLS")
  }

  NetworkModel { id: connectionState }

  IpcHandler {
    target: "desktopBar"
    function reveal(): void { root.barOpen = true; }
    function conceal(): void { root.barOpen = false; }
    function toggle(): void { root.barOpen = !root.barOpen; }
    function powerOpen(): void { root.powerRequested("open"); }
    function powerClose(): void { root.powerRequested("close"); }
    function powerToggle(): void { root.powerRequested("toggle"); }
  }

  Component.onCompleted: {
    refreshTelemetry();
    updateNotificationStatus();
  }

  function parseJson(text, fallback) {
    const rawText = String(text || "").trim();
    if (!rawText)
      return fallback;

    try {
      return JSON.parse(rawText);
    } catch (error) {
      console.error("bar: JSON parse failed: " + error);
      return fallback;
    }
  }

  function updateNotificationStatus() {
    const nextDnd = dndFile.text().trim() === "1";
    const count = Number(countFile.text().trim() || "0");
    dnd = nextDnd;
    notificationUnread = count > 0;

    if (dnd && notificationUnread) {
      notificationStatus = {
        text: "",
        class: "dnd-unread",
        tooltip: "Control center"
      };
    } else if (dnd) {
      notificationStatus = {
        text: "",
        class: "dnd",
        tooltip: "Control center"
      };
    } else if (notificationUnread) {
      notificationStatus = {
        text: "",
        class: "unread",
        tooltip: "Control center"
      };
    } else {
      notificationStatus = {
        text: "",
        class: "normal",
        tooltip: "Control center"
      };
    }
  }

  function updateRecordingState() {
    const startedAt = Number(recordingStateFile.text().trim() || "0");
    recording = isFinite(startedAt) && startedAt > 0;
    recordingStartedAt = recording ? startedAt : 0;
    updateRecordingElapsed();
  }

  function padRecordingUnit(value) {
    return String(Math.max(0, value)).padStart(2, "0");
  }

  function updateRecordingElapsed() {
    if (!recording || recordingStartedAt <= 0) {
      recordingElapsed = "00:00";
      return;
    }

    const elapsed = Math.max(0, Math.floor(Date.now() / 1000 - recordingStartedAt));
    const hours = Math.floor(elapsed / 3600);
    const minutes = Math.floor((elapsed % 3600) / 60);
    const seconds = elapsed % 60;
    recordingElapsed = hours > 0 ? padRecordingUnit(hours) + ":" + padRecordingUnit(minutes) + ":" + padRecordingUnit(seconds) : padRecordingUnit(minutes) + ":" + padRecordingUnit(seconds);
  }

  function refreshTelemetry() {
    metricsProc.running = true;
  }

  SystemClock {
    id: clock
    // Qt timers pause during suspend; seconds precision bounds the stale time
    // after wake without a separate resume listener. Display remains HH:mm.
    precision: SystemClock.Seconds
  }

  BatteryState { id: batterySampler }

  KeyboardState { id: keyboardSampler }

  Timer {
    interval: 1000
    running: root.recording
    repeat: true
    triggeredOnStart: true
    onTriggered: root.updateRecordingElapsed()
  }

  Timer {
    interval: 30000
    running: true
    repeat: true
    onTriggered: root.refreshTelemetry()
  }

  FileView {
    id: dndFile
    path: preferencesDir + "/dnd"
    preload: true
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.updateNotificationStatus()
    onLoadFailed: function () {
      setText("0");
    }
  }

  FileView {
    id: recordingStateFile
    path: Quickshell.env("DESKTOP_SHELL_RECORDING_STATE")
    preload: true
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.updateRecordingState()
    onLoadFailed: function () {
      root.recording = false;
    }
  }

  FileView {
    id: countFile
    path: stateDir + "/count"
    preload: true
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.updateNotificationStatus()
    onLoadFailed: function () {
      setText("0");
    }
  }

  PwObjectTracker {
    objects: Pipewire.nodes.values
  }

  PwObjectTracker {
    objects: root.microphoneLinks
  }

  Process {
    id: metricsProc
    command: [backend, "metrics"]
    stdout: StdioCollector {
      onStreamFinished: root.metrics = root.parseJson(text, root.metrics)
    }
  }
}
