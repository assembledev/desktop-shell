import QtQuick
import Quickshell
import Quickshell.Io
import "TailscaleStatus.js" as Status

Scope {
  id: root
  property string backend: Quickshell.env("DESKTOP_SHELL_BACKEND")
  property bool enabled: false
  property bool detailsActive: false
  property string selectedId: ""
  property var data: ({available:false,connected:false,state:"Loading",peers:[],files:[]})
  property var probe: null
  property int epoch: 0
  property double now: Date.now()
  property double observedAt: 0
  property bool refreshPending: false
  property var knownInbox: null
  property int inboxEpoch: 0
  property int inboxRetryDelay: 0
  readonly property bool monitoring: enabled || detailsActive
  signal filesReceived(var files)
  readonly property var selected: data.peers.find(peer => peer.id === selectedId) || null
  readonly property string probeKey: selectedId + JSON.stringify(selected ? {addresses:selected.addresses,online:selected.online,expired:selected.expired} : null)
  readonly property var online: data.peers.filter(peer => peer.online)
  readonly property var offline: data.peers.filter(peer => !peer.online)
  readonly property bool fresh: observedAt > 0 && now - observedAt < (detailsActive ? 7000 : 35000)
  readonly property bool connected: fresh && data.available && data.connected
  readonly property bool canSend: connected && selected !== null && selected.canSend && selected.online && !selected.expired
  readonly property bool hasProbe: connected && Boolean(selected?.online) && Status.probeMatches(probe, selectedId, now)
  readonly property string connectionText: !fresh ? "Unknown" : !selected ? "Unavailable" : !selected.online ? "Offline" : selected.expired ? "Key expired"
    : hasProbe ? (probe.state === "reachable" ? Status.route(probe.connection, probe.relay) : "Unknown")
    : Status.route(selected.connection, selected.relay)
  readonly property string pingText: !connected || !selected?.online || selected.expired ? "—" : !hasProbe ? "…"
    : probe.state === "reachable" ? Math.max(0.1, probe.milliseconds).toFixed(probe.milliseconds < 10 ? 1 : 0) + " ms"
    : probe.state === "timeout" ? "Timed out" : "Unavailable"

  function refresh() {
    if (!enabled && !detailsActive) return;
    if (sample.running) { refreshPending = true; return; }
    refreshPending = false;
    sample.exec(["timeout", "--kill-after=1s", "10s", backend, "tailscale", "peers-json"]);
  }
  function refreshInbox() {
    if (!monitoring || inbox.running) return;
    inboxTimer.stop();
    inbox.requestEpoch = inboxEpoch;
    inbox.waitSeconds = knownInbox !== null && data.inboxAvailable === true && data.files.length === 0 ? 3600 : 0;
    inbox.exec([backend, "tailscale", "inbox-json", String(inbox.waitSeconds)]);
  }
  function refreshProbe() {
    if (!detailsActive || !connected || !selected?.online || selected.expired || ping.running) return;
    ping.requestEpoch = epoch;
    ping.peerId = selectedId;
    ping.exec(["timeout", "--kill-after=1s", "5s", backend, "tailscale", "ping", selectedId]);
  }
  function resetProbe() {
    epoch++;
    probe = null;
    // Let the bounded old request exit. Its epoch prevents a late result from
    // appearing under another device, even after closing/reopening the panel.
    refreshProbe();
  }
  function snapshot() {
    return Object.assign({}, data, {fresh:fresh,observedAt:observedAt,selectedId:selectedId,probe:hasProbe ? probe : null});
  }
  onEnabledChanged: if (enabled) refresh()
  onDetailsActiveChanged: { resetProbe(); if (detailsActive) { refresh(); refreshInbox(); } }
  onMonitoringChanged: {
    inboxEpoch++;
    if (monitoring) refreshInbox();
    else { inboxTimer.stop(); inbox.running = false; }
  }
  onProbeKeyChanged: resetProbe()
  onConnectedChanged: resetProbe()
  onSelectedChanged: {
    if (!selected || !selected.online) {
      if (probe !== null) { epoch++; probe = null; }
    } else refreshProbe();
  }
  Timer { interval: 1000; running: root.enabled || root.detailsActive; repeat: true; onTriggered: root.now = Date.now() }
  Timer { interval: root.detailsActive ? 2000 : 15000; running: root.enabled || root.detailsActive; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }
  Timer { interval: 2000; running: root.detailsActive && root.connected && Boolean(root.selected?.online); repeat: true; onTriggered: root.refreshProbe() }
  Timer {
    id: inboxTimer
    interval: root.inboxRetryDelay || (root.data.files.length === 0 || root.detailsActive ? 2000 : 15000)
    onTriggered: root.refreshInbox()
  }
  Process {
    id: sample
    stdout: StdioCollector { id: sampleOutput }
    onExited: function(code) {
      let next = null;
      try { if (code === 0) next = JSON.parse(sampleOutput.text); } catch (error) {}
      root.now = Date.now();
      root.observedAt = root.now;
      root.data = Object.assign(next && Array.isArray(next.peers) ? next
        : {available:false,connected:false,state:"Unavailable",peers:[]},
        {files:root.data.files,inboxAvailable:root.data.inboxAvailable === true});
      if (root.refreshPending) Qt.callLater(root.refresh);
    }
  }
  Process {
    id: inbox
    property int requestEpoch: 0
    property int waitSeconds: 0
    stdout: StdioCollector { id: inboxOutput }
    onExited: function(code) {
      if (requestEpoch !== root.inboxEpoch || !root.monitoring) {
        Qt.callLater(root.refreshInbox);
        return;
      }
      let files = null;
      try { if (code === 0) files = Status.waitingFiles(JSON.parse(inboxOutput.text)); } catch (error) {}
      if (files === null) {
        root.data = Object.assign({}, root.data, {inboxAvailable:false});
        root.inboxRetryDelay = Math.min(30000, Math.max(2000, root.inboxRetryDelay * 2));
        inboxTimer.restart();
        return;
      }
      root.inboxRetryDelay = 0;
      const update = Status.inboxUpdate(root.knownInbox, files, true);
      root.knownInbox = update.known;
      root.data = Object.assign({}, root.data, {files:files,inboxAvailable:true});
      if (update.added.length > 0) root.filesReceived(update.added);
      // Seed an empty inbox before waiting, so its first arrival is announced.
      // Even an unexpectedly immediate empty wait response cannot busy-loop.
      if (files.length === 0 && waitSeconds === 0) Qt.callLater(root.refreshInbox);
      else inboxTimer.restart();
    }
  }
  Process {
    id: ping
    property int requestEpoch: 0
    property string peerId: ""
    stdout: StdioCollector { id: pingOutput }
    onExited: function(code) {
      if (requestEpoch !== root.epoch || peerId !== root.selectedId || !root.detailsActive || !root.connected || !root.selected?.online) {
        Qt.callLater(root.refreshProbe);
        return;
      }
      let result = null;
      try { if (code === 0) result = JSON.parse(pingOutput.text); } catch (error) {}
      root.probe = Object.assign({state:"unavailable",milliseconds:null,connection:"unknown"}, result || {}, {peerId:peerId,observedAt:Date.now()});
    }
  }
}
