import QtQuick
import Quickshell
import Quickshell.Networking

Scope {
  id: root

  property bool scannerActive: false
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

    const shouldScan = scannerActive && enabled && hardwareEnabled;
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
    if (!scannerActive || !enabled || !hardwareEnabled || !device)
      return;

    device.scannerEnabled = false;
    scanRestartTimer.restart();
  }

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
