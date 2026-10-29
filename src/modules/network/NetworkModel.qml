import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import "NetworkStatus.js" as Status

Scope {
  id: root

  property string backend: Quickshell.env("DESKTOP_SHELL_BACKEND")
  property bool detailsActive: false
  property var data: ({ available: false, connected: false, interface: "", type: "" })
  property var previousCounters: null
  property var receiveRate: null
  property var transmitRate: null
  property var ping: ({ target: "1.1.1.1", state: "idle", milliseconds: null })
  property var publicIp: ({ state: "idle", address: "" })
  property int epoch: 0
  readonly property bool connected: Boolean(data.connected)
  readonly property var device: Networking.devices.values.find(candidate => candidate.name === root.data.interface) || null
  readonly property var activeNetwork: device && device.type === DeviceType.Wifi
    ? device.networks.values.find(candidate => candidate.connected) || null : null
  readonly property string ssid: String(activeNetwork?.name || data.connection || "")
  readonly property var signalStrength: activeNetwork ? Math.round(activeNetwork.signalStrength * 100) : null
  readonly property string security: {
    if (!activeNetwork)
      return "";
    const value = activeNetwork.security;
    if (value === WifiSecurityType.Sae || value === WifiSecurityType.Wpa3SuiteB192)
      return "WPA3";
    if (value === WifiSecurityType.Wpa2Psk || value === WifiSecurityType.Wpa2Eap)
      return "WPA2";
    if (value === WifiSecurityType.Open)
      return "Open";
    if (value === WifiSecurityType.Owe)
      return "Enhanced open";
    return value === WifiSecurityType.Unknown ? "" : "Secured";
  }
  readonly property string icon: !connected ? "network-off" : data.type === "ethernet" ? "ethernet" : Status.signalLevel(signalStrength)
  readonly property string tooltip: !data.available ? "Network service unavailable" : !connected ? "Disconnected"
    : data.type === "ethernet" ? "Ethernet · " + data.interface : (ssid || "Wi-Fi") + (signalStrength === null ? "" : " · " + signalStrength + "%")
  readonly property string nativeState: JSON.stringify(Networking.devices.values.map(candidate => ({ name: candidate.name, connected: candidate.connected, state: candidate.state })))

  function refresh() {
    sample.refreshPending = sample.running;
    if (sample.refreshPending)
      return;
    sample.requestEpoch = epoch;
    sample.detailed = detailsActive;
    sample.exec(["timeout", "--kill-after=1s", "5s", backend, "network", "snapshot", detailsActive ? "details" : "link"]);
  }

  function refreshPing() {
    probe.refreshPending = detailsActive && connected && probe.running && probe.requestEpoch !== epoch;
    if (!detailsActive || !connected || probe.running)
      return;
    probe.requestEpoch = epoch;
    probe.exec(["timeout", "--kill-after=1s", "3s", backend, "network", "ping"]);
  }

  function refreshPublicIP() {
    publicProbe.refreshPending = detailsActive && connected && publicProbe.running && publicProbe.requestEpoch !== epoch;
    if (!detailsActive || !connected || publicProbe.running)
      return;
    publicProbe.requestEpoch = epoch;
    publicProbe.exec(["timeout", "--kill-after=1s", "10s", backend, "network", "public-ip"]);
  }

  function snapshot() {
    return Object.assign({}, data, { ssid: ssid, signal: signalStrength, security: security,
      detailsActive: detailsActive, receiveBytesPerSecond: receiveRate, transmitBytesPerSecond: transmitRate, ping: ping, publicIp: publicIp });
  }

  onNativeStateChanged: refresh()
  onDetailsActiveChanged: {
    epoch++;
    sample.running = false;
    probe.running = false;
    publicProbe.running = false;
    publicIp = { state: detailsActive ? "pending" : "idle", address: "" };
    previousCounters = null;
    receiveRate = null;
    transmitRate = null;
    ping = { target: "1.1.1.1", state: detailsActive ? "pending" : "idle", milliseconds: null };
    refresh();
    refreshPing();
    refreshPublicIP();
  }

  Timer {
    interval: root.detailsActive ? 2000 : 10000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }
  Timer {
    interval: 2000
    running: root.detailsActive && root.connected
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshPing()
  }
  Timer {
    interval: 30000
    running: root.detailsActive && root.connected
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshPublicIP()
  }
  Process {
    id: sample
    property bool refreshPending: false
    onRunningChanged: {
      if (!running && refreshPending)
        root.refresh();
    }
    property int requestEpoch: 0
    property bool detailed: false
    stdout: StdioCollector { id: sampleOutput }
    onExited: function(exitCode) {
      if (requestEpoch !== root.epoch)
        return;
      let next;
      try {
        next = exitCode === 0 ? JSON.parse(sampleOutput.text) : null;
      } catch (error) { next = null; }
      if (!next || typeof next.connected !== "boolean")
        next = { available: false, connected: false, interface: "", type: "" };
      const changed = next.interface !== root.data.interface || next.connected !== root.connected;
      if (changed) {
        root.epoch++;
        root.previousCounters = null;
        root.receiveRate = null;
        root.transmitRate = null;
        root.probeReset();
      }
      if (detailed && root.detailsActive && next.connected) {
        const traffic = Status.traffic(root.previousCounters, next, Date.now());
        root.previousCounters = traffic.baseline;
        root.receiveRate = traffic.receive;
        root.transmitRate = traffic.transmit;
      }
      root.data = !detailed && !changed ? Object.assign({}, root.data, next) : next;
      if (changed) {
        root.refreshPing();
        root.refreshPublicIP();
      }
    }
  }
  function probeReset() {
    probe.running = false;
    publicProbe.running = false;
    publicIp = { state: detailsActive ? "pending" : "idle", address: "" };
    ping = { target: "1.1.1.1", state: detailsActive ? "pending" : "idle", milliseconds: null };
  }
  Process {
    id: probe
    property bool refreshPending: false
    onRunningChanged: {
      if (!running && refreshPending)
        root.refreshPing();
    }
    property int requestEpoch: 0
    stdout: StdioCollector { id: probeOutput }
    onExited: function(exitCode) {
      if (requestEpoch !== root.epoch || !root.detailsActive || !root.connected)
        return;
      try {
        root.ping = exitCode === 0 ? JSON.parse(probeOutput.text) : { target: "1.1.1.1", state: "unavailable", milliseconds: null };
      } catch (error) {
        root.ping = { target: "1.1.1.1", state: "unavailable", milliseconds: null };
      }
    }
  }
  Process {
    id: publicProbe
    property bool refreshPending: false
    onRunningChanged: {
      if (!running && refreshPending)
        root.refreshPublicIP();
    }
    property int requestEpoch: 0
    stdout: StdioCollector { id: publicOutput }
    onExited: function(exitCode) {
      if (requestEpoch !== root.epoch || !root.detailsActive || !root.connected)
        return;
      let result;
      try {
        result = exitCode === 0 ? JSON.parse(publicOutput.text) : null;
      } catch (error) { result = null; }
      if (result && result.state === "ready" && typeof result.address === "string" && result.address.length > 0)
        root.publicIp = result;
      else
        root.publicIp = { state: "unavailable", address: "", error: exitCode === 124 ? "timeout" : result?.error || "connection" };
    }
  }
}
