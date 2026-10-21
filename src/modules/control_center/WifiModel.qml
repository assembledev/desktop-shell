import QtQuick
import Quickshell
import Quickshell.Networking

Scope {
  id: root

  property bool scannerActive: false
  property bool commandScanActive: false
  property var scannerDevice: null
  property bool scanPending: false

  readonly property bool backendAvailable: Networking.backend === NetworkBackendType.NetworkManager
  readonly property bool enabled: Networking.wifiEnabled
  readonly property bool hardwareEnabled: Networking.wifiHardwareEnabled
  readonly property var devices: Networking.devices.values.filter(function(candidate) {
    return candidate && candidate.type === DeviceType.Wifi;
  })
  readonly property var device: {
    for (const candidate of devices) {
      if (candidate.connected)
        return candidate;
    }
    return devices.length > 0 ? devices[0] : null;
  }
  readonly property bool adapterAvailable: backendAvailable && hardwareEnabled && device !== null
  readonly property bool connected: Boolean(device?.connected)
  readonly property var networks: {
    if (!device)
      return [];

    return [...device.networks.values].sort(function(left, right) {
      if (left.connected !== right.connected)
        return left.connected ? -1 : 1;
      if (left.known !== right.known)
        return left.known ? -1 : 1;
      return Number(right.signalStrength || 0) - Number(left.signalStrength || 0);
    });
  }
  readonly property var activeNetwork: {
    for (const network of networks) {
      if (network.connected)
        return network;
    }
    return null;
  }
  readonly property var changingNetwork: {
    for (const network of networks) {
      if (network.stateChanging)
        return network;
    }
    return null;
  }
  readonly property string ssid: String(activeNetwork?.name || "")
  readonly property int signal: Math.round(Number(activeNetwork?.signalStrength || 0) * 100)
  readonly property bool busy: changingNetwork !== null
  readonly property bool connecting: device?.state === ConnectionState.Connecting
    || changingNetwork?.state === ConnectionState.Connecting
  readonly property bool disconnecting: device?.state === ConnectionState.Disconnecting
    || changingNetwork?.state === ConnectionState.Disconnecting

  function syncScanner() {
    if (scannerDevice && scannerDevice !== device)
      scannerDevice.scannerEnabled = false;

    scannerDevice = device;
    if (!scannerDevice)
      return;

    const shouldScan = (scannerActive || commandScanActive) && enabled && hardwareEnabled;
    scannerDevice.scannerEnabled = shouldScan;
    if (scanPending && shouldScan) {
      scanPending = false;
      requestScan();
    }
  }

  function setEnabled(nextEnabled) {
    Networking.wifiEnabled = nextEnabled;
  }

  function connectNetwork(network, password) {
    if (!network || network.stateChanging)
      return;
    if (password)
      network.connectWithPsk(password);
    else
      network.connect();
  }

  function disconnectNetwork(network) {
    if (network && !network.stateChanging)
      network.disconnect();
  }

  function requestScan() {
    if ((!scannerActive && !commandScanActive) || !enabled || !hardwareEnabled || !device)
      return;

    device.scannerEnabled = false;
    scanRestartTimer.restart();
  }

  function snapshot() {
    return {
      available: backendAvailable && device !== null, hardwareEnabled: hardwareEnabled,
      enabled: enabled, connected: connected, busy: busy, ssid: ssid, signal: signal,
      scanning: enabled && hardwareEnabled && (commandScanActive || scannerActive),
      networks: networks.map(function(network) {
        return { ssid: String(network.name || ""), known: Boolean(network.known),
                 connected: Boolean(network.connected), busy: Boolean(network.stateChanging),
                 signal: Math.round(Number(network.signalStrength || 0) * 100) };
      })
    };
  }

  function command(action, name) {
    if (!backendAvailable || !device || !hardwareEnabled)
      return { error: { code: "unavailable", message: "Wi-Fi adapter is unavailable or hardware-blocked" } };
    if (action === "on" || action === "off") {
      setEnabled(action === "on");
      return { accepted: true, enabled: action === "on" };
    }
    if (!enabled)
      return { error: { code: "unavailable", message: "Wi-Fi is disabled" } };
    if (action === "scan") {
      commandScanActive = true;
      commandScanTimer.restart();
      requestScan();
      return { accepted: true, action: "scan" };
    }
    const matches = networks.filter(function(network) { return network.name === name; });
    if (matches.length !== 1)
      return { error: { code: "not-found", message: "No unique visible Wi-Fi network matches the SSID" } };
    const network = matches[0];
    if (busy || network.stateChanging)
      return { error: { code: "busy", message: "A Wi-Fi operation is already in progress" } };
    if (action === "connect") {
      if (network.connected)
        return { accepted: true, ssid: name, connected: true };
      if (!network.known)
        return { error: { code: "authentication-required", message: "Authenticate in the Wi-Fi panel first; CLI connects saved networks" } };
      connectNetwork(network, "");
    } else if (action === "disconnect") {
      disconnectNetwork(network);
    } else {
      return { error: { code: "invalid-argument", message: "Unknown Wi-Fi operation" } };
    }
    return { accepted: true, ssid: name, action: action };
  }

  Timer {
    id: commandScanTimer
    interval: 15000
    onTriggered: root.commandScanActive = false
  }

  onCommandScanActiveChanged: syncScanner()
  onDeviceChanged: syncScanner()
  onScannerActiveChanged: syncScanner()
  onEnabledChanged: {
    scanPending = enabled;
    syncScanner();
  }
  onHardwareEnabledChanged: syncScanner()

  Component.onCompleted: syncScanner()
  Component.onDestruction: {
    if (scannerDevice)
      scannerDevice.scannerEnabled = false;
  }

  Timer {
    id: scanRestartTimer
    interval: 1
    repeat: false
    onTriggered: root.syncScanner()
  }
}
