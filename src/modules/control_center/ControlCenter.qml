import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import Quickshell.Services.Notifications
import "../common"

Scope {
  id: root

  Theme {
    id: theme
  }

  ShellConfig { id: shellConfig }
  MotionTransition {
    id: mainSurfaceTransition
    requested: root.open
  }
  PopupLifecycle {
    requested: root.open
    surface: mainWindow
    onDismissed: root.open = false
  }
  MotionTransition {
    id: osdSurfaceTransition
    requested: root.osdVisible
  }
  MotionTransition {
    id: popupSurfaceTransition
    requested: notificationPopupModel.count > 0
  }

  WifiModel {
    id: wifi
    scannerActive: root.open && root.page === "wifi"
  }

  property string backend: Quickshell.env("CONTROL_CENTER_BACKEND")
  property string stateDir: Quickshell.env("CONTROL_CENTER_STATE_DIR")
  property string preferencesDir: Quickshell.env("DESKTOP_SHELL_PREFERENCES_DIR")
  property bool open: false
  property bool dnd: false
  property string page: "main"
  property string displayedPage: "main"
  property int pageDirection: 1
  readonly property bool wifiEnabled: wifi.enabled
  readonly property bool wifiConnected: wifi.connected
  readonly property string wifiSsid: wifi.ssid
  readonly property var wifiNetworks: wifi.networks
  property string wifiError: ""
  property string pendingSsid: ""
  property string pendingPassword: ""
  property string connectionTargetSsid: ""
  readonly property bool wifiBusy: wifi.busy
  property bool bluetoothAvailable: false
  property bool bluetoothEnabled: false
  property bool bluetoothDiscoverable: false
  property bool bluetoothPairable: false
  property bool bluetoothDiscovering: false
  property bool bluetoothStatusReady: false
  property bool bluetoothDevicesReady: false
  property var bluetoothDevices: []
  property string bluetoothOperation: ""
  property string bluetoothOperationAddress: ""
  property string bluetoothOperationName: ""
  property string bluetoothError: ""
  property bool bluetoothSessionActive: false
  property bool bluetoothSessionClosing: false
  property bool bluetoothDiscoveryStarted: false
  property bool bluetoothDiscoveryStopRequested: false
  property string pendingBluetoothForgetAddress: ""
  readonly property bool bluetoothBusy: bluetoothOperation.length > 0
  property int bluetoothGeneration: 0
  property double lastBluetoothPollAt: 0
  readonly property int bluetoothPollInterval: 3000
  readonly property int bluetoothStaleAfter: 10000
  readonly property int backendQueryTimeout: 6
  property real brightness: 0
  property string brightnessBackend: "backlight"
  property bool brightnessSupported: false
  property bool brightnessWritable: false
  property int pendingBrightnessPercent: 0
  property bool brightnessReady: false
  property bool volumeReady: false
  readonly property int osdTimeout: 1100
  readonly property int osdRowHeight: 38
  readonly property int osdRowSpacing: 10
  readonly property int osdVerticalPadding: 24
  readonly property int osdRowCount: osdModel.count
  readonly property bool osdVisible: osdRowCount > 0
  readonly property int osdBoxHeight: osdVerticalPadding
      + osdRowCount * osdRowHeight
      + Math.max(0, osdRowCount - 1) * osdRowSpacing
  readonly property var osdKinds: ({
    brightness: { icon: "󰃠", accent: theme.yellow },
    volume: { icon: "", accent: theme.blue },
    fallback: { icon: "󰘳", accent: theme.purple }
  })
  property var notifications: []
  property var clearedNotifications: []
  property var expandedNotificationGroups: ({})
  property double notificationTimelineNow: Date.now()
  property var notificationPopupById: ({})
  property var metrics: ({ cpu: 0, ram: 0, ramText: "--", vram: 0, vramText: "--", hasVram: false })
  property var power: ({ supported: false, profile: "", choices: [] })
  property bool focusMode: false
  property bool focusBarOpen: false
  property bool outputExpanded: false
  property bool inputExpanded: false
  readonly property int popupTimeout: 6500
  readonly property int clearUndoTimeout: 6000
  readonly property int notificationPopupDefaultWidth: 386
  readonly property int notificationPopupMaxWidth: 560
  readonly property int notificationActionSpacing: 6

  property var sink: Pipewire.defaultAudioSink
  property var source: Pipewire.defaultAudioSource
  readonly property bool audioDetailsActive: open
  readonly property var audioNodes: audioDetailsActive ? Pipewire.nodes.values : []
  readonly property var outputDevices: audioNodes.filter(function(node) {
    return Boolean(node?.audio && node.ready && !node.isStream && node.isSink)
  })
  readonly property var inputDevices: audioNodes.filter(function(node) {
    return Boolean(node?.audio && node.ready && !node.isStream && !node.isSink)
  })
  readonly property var appStreams: audioNodes.filter(function(node) {
    return Boolean(node?.audio && node.isStream)
  })

  SequentialAnimation {
    id: pageTransition

    ParallelAnimation {
      MotionNumberAnimation {
        target: pageLoader
        property: "opacity"
        to: 0
        role: MotionNumberAnimation.SurfaceExit
      }
      MotionNumberAnimation {
        target: pageLoader
        property: "x"
        to: -root.pageDirection * 18
        role: MotionNumberAnimation.SurfaceExit
      }
    }
    ScriptAction {
      script: {
        root.displayedPage = root.page;
        pageLoader.x = root.pageDirection * 18;
      }
    }
    ParallelAnimation {
      MotionNumberAnimation {
        target: pageLoader
        property: "opacity"
        to: 1
        role: MotionNumberAnimation.Content
      }
      MotionNumberAnimation {
        target: pageLoader
        property: "x"
        to: 0
        role: MotionNumberAnimation.Content
      }
    }
  }

  function clamp(value, minValue, maxValue) {
    return Math.max(minValue, Math.min(maxValue, value));
  }

  function osdIndex(kind) {
    for (let i = 0; i < osdModel.count; i++) {
      if (osdModel.get(i).kind === kind)
        return i;
    }
    return -1;
  }

  function osdKind(kind) {
    return osdKinds[kind] || osdKinds.fallback;
  }

  function osdIcon(kind) {
    return osdKind(kind).icon;
  }

  function osdAccent(kind) {
    return osdKind(kind).accent;
  }

  function armOsdSweep() {
    if (osdModel.count === 0)
      return;

    const now = Date.now();
    let nextExpiry = osdModel.get(0).expiresAt;
    for (let i = 1; i < osdModel.count; i++)
      nextExpiry = Math.min(nextExpiry, osdModel.get(i).expiresAt);

    osdSweepTimer.interval = Math.max(16, nextExpiry - now);
    osdSweepTimer.restart();
  }

  function sweepOsd() {
    const now = Date.now();
    for (let i = osdModel.count - 1; i >= 0; i--) {
      if (osdModel.get(i).expiresAt <= now)
        osdModel.remove(i);
    }
    armOsdSweep();
  }

  function showOsd(kind, value, label) {
    const level = clamp(Number(value) || 0, 0, 1);
    const text = label === undefined ? Math.round(level * 100) + "%" : String(label);
    const entry = {
      kind: kind,
      osdLevel: level,
      displayText: text,
      expiresAt: Date.now() + osdTimeout
    };
    const index = osdIndex(kind);
    if (index >= 0)
      osdModel.set(index, entry);
    else
      osdModel.append(entry);
    armOsdSweep();
  }

  function updateNotificationCount() {
    countFile.setText(String(notifications.length));
  }

  function itemNotification(item) {
    return item?.notification || null;
  }

  function notificationAppName(notification) {
    return String(notification?.appName || "Application");
  }

  function notificationIsResident(notification) {
    return Boolean(notification?.resident)
      || hintBoolean(notification, "resident", false);
  }

  function notificationPopupPersistent(notification) {
    return notificationIsResident(notification)
      || Number(notification?.expireTimeout || -1) === 0
      || Boolean(notification?.hasInlineReply);
  }

  function notificationPopupDuration(notification) {
    const requested = Number(notification?.expireTimeout || -1);
    return requested > 0 ? Math.max(1000, requested) : popupTimeout;
  }

  function notificationIsCritical(notification) {
    const urgency = notification?.urgency;
    if (typeof urgency === "number")
      return urgency >= 2;

    const hint = hintValue(notification, "urgency");
    if (typeof hint === "number")
      return hint >= 2;

    const normalized = String(urgency ?? hint ?? "").trim().toLowerCase();
    return normalized === "critical" || normalized === "2";
  }

  function relativeNotificationTime(timestamp) {
    const now = notificationTimelineNow;
    const elapsed = Math.max(0, now - Number(timestamp || now));
    const seconds = Math.floor(elapsed / 1000);
    const minutes = Math.floor(elapsed / 60000);
    if (seconds < 60)
      return seconds + "s";
    if (minutes < 60)
      return minutes + "m";

    const hours = Math.floor(minutes / 60);
    if (hours < 24)
      return hours + "h";

    const days = Math.floor(hours / 24);
    if (days < 7)
      return days + "d";

    return Qt.formatDateTime(new Date(Number(timestamp)), "MMM d");
  }

  function notificationGroups(priority) {
    const groupsByKey = {};
    const groups = [];

    for (const item of notifications) {
      const notification = itemNotification(item);
      const critical = notificationIsCritical(notification);
      const persistent = notificationPopupPersistent(notification);
      const needsAttention = critical || persistent;
      if (needsAttention !== priority)
        continue;

      const appName = notificationAppName(notification);
      const key = (priority ? "priority:" : "recent:") + appName.toLowerCase();
      let group = groupsByKey[key];
      if (!group) {
        group = {
          key: key,
          appName: appName,
          items: [],
          critical: false,
          resident: false,
          latestTime: Number(item?.time || 0)
        };
        groupsByKey[key] = group;
        groups.push(group);
      }

      group.items.push(item);
      group.critical = group.critical || critical;
      group.resident = group.resident || persistent;
      group.latestTime = Math.max(group.latestTime, Number(item?.time || 0));
    }

    return groups;
  }

  function notificationGroupExpanded(key) {
    return Boolean(expandedNotificationGroups[String(key)]);
  }

  function toggleNotificationGroup(key) {
    const next = Object.assign({}, expandedNotificationGroups);
    const normalized = String(key);
    next[normalized] = !next[normalized];
    expandedNotificationGroups = next;
  }

  function deviceName(node) {
    return node?.nickname || node?.description || node?.name || "Device";
  }

  function streamProperty(node, name) {
    return String(node?.properties?.[name] || "").trim();
  }

  function sameStreamLabel(left, right) {
    return left.localeCompare(right, undefined, { sensitivity: "accent" }) === 0;
  }

  function streamApplicationName(node) {
    return streamProperty(node, "application.name") || node?.description || node?.name || "App";
  }

  function streamName(node) {
    const application = streamApplicationName(node);
    const media = streamProperty(node, "media.name");
    return media && !sameStreamLabel(media, application) ? media : application;
  }

  function streamDirection(node) {
    const mediaClass = streamProperty(node, "media.class");
    if (mediaClass === "Stream/Input/Audio")
      return "Recording";
    if (mediaClass === "Stream/Output/Audio")
      return "Playback";
    return "Audio";
  }

  function streamSubtitle(node) {
    const application = streamApplicationName(node);
    const title = streamName(node);
    const role = streamProperty(node, "media.role");
    const details = [];
    if (!sameStreamLabel(application, title))
      details.push(application);
    details.push(streamDirection(node));
    if (role && !details.some(function(detail) { return sameStreamLabel(detail, role); }))
      details.push(role);
    return details.join(" · ");
  }

  function streamIcon(node) {
    return streamProperty(node, "media.class") === "Stream/Input/Audio" ? "" : "󰎆";
  }

  function streamAccent(node) {
    return streamProperty(node, "media.class") === "Stream/Input/Audio" ? theme.purple : theme.blue;
  }

  function signalGlyph(value) {
    if (value >= 80)
      return "▂▄▆█";
    if (value >= 55)
      return "▂▄▆_";
    if (value >= 30)
      return "▂▄__";
    return "▂___";
  }

  function powerIcon(profile) {
    if (profile === "performance")
      return "";
    if (profile === "quiet" || profile === "low-power" || profile === "power-saver")
      return "";
    return "";
  }

  function notificationActions(actions) {
    return (actions || []).filter(function(action) {
      const label = String(action?.text || "").trim();
      return action && label.length > 0 && action.invoke;
    });
  }

  function visibleNotificationActions(notification) {
    return notificationActions(notification?.actions).filter(function(action) {
      return String(action?.identifier || "") !== "default";
    });
  }

  function defaultNotificationAction(notification) {
    const actions = notificationActions(notification?.actions);
    for (let i = 0; i < actions.length; i++) {
      if (String(actions[i]?.identifier || "") === "default")
        return actions[i];
    }
    return null;
  }

  function actionLabel(action) {
    return String(action?.text || "").trim();
  }

  function actionEntries(actions, notification) {
    return (actions || []).map(function(action) {
      return {
        action: action,
        notification: notification
      };
    });
  }

  function iconSource(icon) {
    const value = String(icon || "").trim();
    if (value.length === 0)
      return "";
    if (value.startsWith("/") || value.startsWith("file:") || value.startsWith("image:") || value.startsWith("qrc:"))
      return value;
    return Quickshell.iconPath(value, true);
  }

  function notificationVisualSource(notification) {
    const image = String(notification?.image || "").trim();
    if (image.length > 0) {
      // Quickshell converts a themed freedesktop image-path hint into an
      // unchecked image://icon URL before exposing Notification.image. Resolve
      // that original theme name through the checked public API so a missing
      // icon becomes our normal fallback instead of a missing-texture image.
      let hintedImage = hintValue(notification, "image-path");
      if (hintedImage === undefined || hintedImage === null || hintedImage === "")
        hintedImage = hintValue(notification, "image_path");
      hintedImage = String(hintedImage || "").trim();

      if (hintedImage.length > 0 && image === Quickshell.iconPath(hintedImage))
        return Quickshell.iconPath(hintedImage, true);

      return image;
    }
    return iconSource(notification?.appIcon || "");
  }

  function notificationActionIconSource(notification, action) {
    if (!notification?.hasActionIcons)
      return "";
    return iconSource(action?.identifier || "");
  }

  function notificationActionsWidth(actions, notification) {
    const current = actions || [];
    let width = 0;
    for (let i = 0; i < current.length; i++) {
      if (i > 0)
        width += notificationActionSpacing;
      const iconWidth = notificationActionIconSource(notification, current[i]).length > 0 ? 22 : 0;
      width += Math.max(72, notificationActionFont.advanceWidth(actionLabel(current[i])) + 22 + iconWidth);
    }
    return width;
  }

  function notificationPopupWidth() {
    let width = notificationPopupDefaultWidth;
    for (let i = 0; i < notificationPopupModel.count; i++) {
      const popup = popupData(notificationPopupModel.get(i).popupId);
      const notification = itemNotification(popup);
      const contentWidth = notificationActionsWidth(visibleNotificationActions(notification), notification) + 26;
      width = Math.max(width, Math.min(notificationPopupMaxWidth, contentWidth));
    }
    return width;
  }

  function invokeNotificationAction(action) {
    if (action?.invoke)
      action.invoke();
  }

  function invokeDefaultNotificationAction(notification) {
    invokeNotificationAction(defaultNotificationAction(notification));
  }

  function wifiSummaryText() {
    if (!wifi.backendAvailable || !wifi.hardwareEnabled || !wifi.device)
      return "Unavailable";
    if (!wifiEnabled)
      return "Off";
    if (wifi.connecting)
      return wifi.changingNetwork?.name ? "Joining " + wifi.changingNetwork.name : "Connecting";
    if (wifi.disconnecting)
      return "Disconnecting";
    if (wifiConnected)
      return wifiSsid.length > 0 ? wifiSsid : "Connected";
    return "On · no network";
  }

  function wifiAdapterAvailable() {
    return wifiEnabled && wifi.adapterAvailable;
  }

  function wifiHeaderTitle() {
    if (wifiConnected && wifiSsid.length > 0)
      return wifiSsid;
    return "Wi-Fi";
  }

  function wifiHeaderSubtitle() {
    if (!wifi.backendAvailable)
      return "NetworkManager is unavailable";
    if (!wifi.hardwareEnabled || !wifi.device)
      return "No wireless adapter is available";
    if (!wifiEnabled)
      return "Wireless is disabled";
    if (wifi.connecting)
      return wifi.changingNetwork?.name
        ? "Connecting to " + wifi.changingNetwork.name + "…"
        : "Connecting…";
    if (wifi.disconnecting)
      return "Disconnecting…";
    if (wifiConnected)
      return "Connected · " + wifi.signal + "% signal";
    return "On · choose a network below";
  }

  function wifiSignal(network) {
    return Math.round(Number(network?.signalStrength || 0) * 100);
  }

  function wifiNetworkNeedsPsk(network) {
    return network?.security === WifiSecurityType.WpaPsk
      || network?.security === WifiSecurityType.Wpa2Psk
      || network?.security === WifiSecurityType.Sae;
  }

  function wifiNetworkSecurity(network) {
    if (network?.security === WifiSecurityType.Open)
      return "Open network";
    if (network?.security === WifiSecurityType.Owe)
      return "Enhanced open";
    if (network?.security === WifiSecurityType.Unknown)
      return "Security unknown";
    return "Secured";
  }

  function wifiNetworkDescription(network) {
    const signal = wifiSignal(network);
    if (network?.connected)
      return "Connected · " + signal + "% signal";

    const access = wifiNetworkSecurity(network);
    if (network?.known)
      return "Saved · " + access + " · " + signal + "%";
    return access + " · " + signal + "%";
  }

  function wifiNetworkAction(network) {
    if (network?.state === ConnectionState.Connecting)
      return "Connecting…";
    if (network?.state === ConnectionState.Disconnecting)
      return "Disconnecting…";
    if (network?.connected)
      return "Disconnect";
    return network?.known ? "Connect" : "Join";
  }

  function handleWifiConnectionFailure(network, reason) {
    if (reason === ConnectionFailReason.NoSecrets && wifiNetworkNeedsPsk(network)) {
      const failedSsid = String(network?.name || "");
      if (failedSsid !== connectionTargetSsid)
        return;
      requestWifiPassword(network);
      wifiError = "A password is required for " + pendingSsid;
      return;
    }

    if (reason === ConnectionFailReason.WifiAuthTimeout
        || reason === ConnectionFailReason.WifiClientFailed) {
      wifiError = "Authentication failed for " + String(network?.name || "this network");
    } else if (reason === ConnectionFailReason.WifiNetworkLost) {
      wifiError = "The network disappeared while connecting";
    } else {
      wifiError = "Could not connect to " + String(network?.name || "this network");
    }
  }

  function bluetoothConnectedDevices() {
    return bluetoothDevices.filter(function(device) { return Boolean(device?.connected); });
  }

  function bluetoothPairedDevices() {
    return bluetoothDevices.filter(function(device) { return Boolean(device?.paired); });
  }

  function bluetoothNearbyDevices() {
    return bluetoothDevices.filter(function(device) { return !Boolean(device?.paired); });
  }

  function bluetoothSummaryText() {
    if (!bluetoothStatusReady)
      return "Checking";
    if (!bluetoothAvailable)
      return "Unavailable";
    if (bluetoothOperation === "enable")
      return "Turning on";
    if (bluetoothOperation === "disable")
      return "Turning off";
    if (!bluetoothEnabled)
      return "Off";

    const connected = bluetoothConnectedDevices();
    if (connected.length === 1)
      return connected[0].name;
    if (connected.length > 1)
      return connected.length + " connected";
    return "On · private";
  }

  function bluetoothHeaderTitle() {
    if (!bluetoothStatusReady)
      return "Bluetooth";
    const connected = bluetoothConnectedDevices();
    return connected.length === 1 ? connected[0].name : "Bluetooth";
  }

  function bluetoothHeaderSubtitle() {
    if (!bluetoothStatusReady)
      return "Checking Bluetooth state…";
    if (!bluetoothAvailable)
      return "No Bluetooth adapter is available";
    if (bluetoothOperation === "enable")
      return "Turning Bluetooth on…";
    if (bluetoothOperation === "disable")
      return "Turning Bluetooth off…";
    if (!bluetoothEnabled)
      return "Radio is disabled";

    const connected = bluetoothConnectedDevices().length;
    if (bluetoothDiscoverable)
      return connected > 0 ? connected + " connected · visible for pairing" : "Visible for pairing";
    return connected > 0 ? connected + " connected · hidden" : "On · hidden from new devices";
  }

  function bluetoothDeviceIcon(device) {
    const icon = String(device?.icon || "").toLowerCase();
    if (icon.includes("audio") || icon.includes("headset") || icon.includes("headphones"))
      return "";
    if (icon.includes("keyboard"))
      return "";
    if (icon.includes("mouse") || icon.includes("pointing"))
      return "󰍽";
    if (icon.includes("game"))
      return "";
    if (icon.includes("phone"))
      return "";
    if (icon.includes("computer"))
      return "";
    return "󰂯";
  }

  function bluetoothDeviceDescription(device) {
    const details = [];
    if (device?.connected)
      details.push("Connected");
    else if (device?.paired)
      details.push("Paired");
    else
      details.push("Nearby");

    if (device?.battery !== null && device?.battery !== undefined)
      details.push(device.battery + "% battery");
    else if (!device?.paired && device?.signal !== null && device?.signal !== undefined)
      details.push(device.signal + "% signal");
    return details.join(" · ");
  }

  function bluetoothDeviceAction(device) {
    if (bluetoothOperationAddress === device?.address) {
      if (bluetoothOperation === "pair")
        return "Pairing…";
      if (bluetoothOperation === "connect")
        return "Connecting…";
      if (bluetoothOperation === "disconnect")
        return "Disconnecting…";
    }
    if (device?.connected)
      return "Disconnect";
    if (device?.paired)
      return "Connect";
    return "Pair";
  }

  function cleanBluetoothError(message, fallback) {
    const cleaned = String(message || "")
      .replace(/\x1b\[[0-9;]*m/g, "")
      .replace(/^\s*Failed to [^:]+:\s*/i, "")
      .replace(/^\s*Error:\s*/i, "")
      .replace(/org\.bluez\.Error\.[A-Za-z]+\s*/g, "")
      .replace(/\s+/g, " ")
      .trim();
    return cleaned.length > 0 ? cleaned : fallback;
  }

  function hintValue(notification, name) {
    const hints = notification?.hints || {};
    return hints[name];
  }

  function hintBoolean(notification, name, fallback) {
    const value = hintValue(notification, name);
    if (value === undefined || value === null)
      return fallback;
    if (typeof value === "boolean")
      return value;
    if (typeof value === "number")
      return value !== 0;

    const normalized = String(value).trim().toLowerCase();
    if (["1", "true", "yes", "on"].includes(normalized))
      return true;
    if (["0", "false", "no", "off"].includes(normalized))
      return false;

    return fallback;
  }

  function escapeNotificationText(value) {
    return String(value || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/\"/g, "&quot;")
      .replace(/'/g, "&#39;");
  }

  function safeNotificationLink(value) {
    const link = String(value || "").trim();
    const match = link.match(/^([a-z][a-z0-9+.-]*):/i);
    if (!match)
      return "";

    const scheme = match[1].toLowerCase();
    return ["file", "http", "https", "mailto"].includes(scheme) ? link : "";
  }

  function sanitizeNotificationBody(body) {
    return String(body || "").replace(/<[^>]*>/g, function(tag) {
      const normalized = tag.trim().toLowerCase();
      const simpleTag = normalized.match(/^<\s*(\/?)\s*(b|i|u)\s*>$/);
      if (simpleTag)
        return "<" + simpleTag[1] + simpleTag[2] + ">";
      if (/^<\s*br\s*\/?\s*>$/.test(normalized))
        return "<br>";
      if (/^<\s*\/\s*a\s*>$/.test(normalized))
        return "</a>";

      const anchor = tag.match(/^<\s*a\b[^>]*\bhref\s*=\s*(["'])(.*?)\1[^>]*>$/i);
      if (anchor) {
        const link = safeNotificationLink(anchor[2]);
        return link.length > 0 ? "<a href=\"" + escapeNotificationText(link) + "\">" : "";
      }

      const image = tag.match(/^<\s*img\b[^>]*\balt\s*=\s*(["'])(.*?)\1[^>]*>$/i);
      if (image)
        return escapeNotificationText(image[2]);
      if (/^<\s*img\b/i.test(normalized))
        return "";

      return escapeNotificationText(tag);
    });
  }

  function openNotificationLink(value) {
    const link = safeNotificationLink(value);
    if (link.length > 0)
      Qt.openUrlExternally(link);
  }

  function notificationProgress(notification) {
    let rawValue = hintValue(notification, "value");
    if (rawValue === undefined || rawValue === null || rawValue === "")
      rawValue = hintValue(notification, "has-percentage");
    if (rawValue === undefined || rawValue === null || rawValue === "")
      return { visible: false, value: 0, text: "" };

    const value = Number(rawValue);
    let maximum = Number(hintValue(notification, "value-max"));
    if (!isFinite(maximum) || maximum <= 0)
      maximum = 100;
    if (!isFinite(value) || value < 0)
      return { visible: false, value: 0, text: "" };

    const fraction = clamp(value / maximum, 0, 1);
    return {
      visible: true,
      value: fraction,
      text: Math.round(fraction * 100) + "%"
    };
  }

  function notificationPolicy(notification) {
    const popup = hintBoolean(notification, "x-desktop-shell-popup", true);
    const bypassDnd = hintBoolean(notification, "x-desktop-shell-bypass-dnd", false);
    const suppressSound = hintBoolean(notification, "suppress-sound", false);
    // Blueman marks only its routine connect/disconnect notifications as
    // transient. Keep those visible, but do not turn device state changes into
    // audible alerts; authentication and error notifications remain audible.
    const silentBluetoothConnection = String(notification?.appName || "").trim().toLowerCase() === "blueman"
      && Boolean(notification?.transient);
    const allowedByDnd = !dnd || bypassDnd;

    return {
      popup: popup && allowedByDnd,
      sound: !suppressSound && !silentBluetoothConnection && allowedByDnd
    };
  }

  function setNodeVolume(node, value) {
    if (node?.ready && node?.audio) {
      node.audio.volume = clamp(value, 0, 1.5);
      node.audio.muted = false;
    }
  }

  function toggleNodeMute(node) {
    if (node?.ready && node?.audio)
      node.audio.muted = !node.audio.muted;
  }

  function removeNotification(id, dismissOriginal) {
    const popupItem = popupData(id);
    const index = notifications.findIndex(function(n) { return n.id === id; });
    if (index < 0) {
      const clearedIndex = clearedNotifications.findIndex(function(n) { return n.id === id; });
      if (clearedIndex >= 0) {
        const nextCleared = clearedNotifications.slice();
        nextCleared.splice(clearedIndex, 1);
        clearedNotifications = nextCleared;
        if (clearedNotifications.length === 0)
          clearUndoTimer.stop();
      }
      if (popupIndex(id) >= 0)
        hidePopup(id, false);
      if (dismissOriginal && popupItem?.notification)
        popupItem.notification.dismiss();
      return;
    }

    const item = notifications[index];
    const next = notifications.slice();
    next.splice(index, 1);
    notifications = next;
    hidePopup(id, false);
    updateNotificationCount();

    if (dismissOriginal && item?.notification)
      item.notification.dismiss();
  }

  function dismissNotification(id) {
    removeNotification(id, true);
  }

  function clearNotifications() {
    const current = notifications.slice();
    if (current.length === 0)
      return;

    if (clearedNotifications.length > 0)
      finalizeClearNotifications();

    notifications = [];
    clearedNotifications = current;
    expandedNotificationGroups = ({});
    while (notificationPopupModel.count > 0)
      hidePopup(notificationPopupModel.get(0).popupId);
    updateNotificationCount();
    clearUndoTimer.restart();
  }

  function undoClearNotifications() {
    if (clearedNotifications.length === 0)
      return;

    clearUndoTimer.stop();
    const restored = clearedNotifications.slice();
    clearedNotifications = [];
    notifications = restored.concat(notifications).sort(function(a, b) {
      return Number(b?.time || 0) - Number(a?.time || 0);
    });
    updateNotificationCount();
  }

  function finalizeClearNotifications() {
    clearUndoTimer.stop();
    const current = clearedNotifications.slice();
    clearedNotifications = [];

    for (let i = 0; i < current.length; i++) {
      if (current[i]?.notification)
        current[i].notification.dismiss();
    }
  }

  function popupIndex(id) {
    for (let i = 0; i < notificationPopupModel.count; i++) {
      if (notificationPopupModel.get(i).popupId === id)
        return i;
    }
    return -1;
  }

  function setPopupData(item) {
    const next = Object.assign({}, notificationPopupById);
    next[String(item.id)] = item;
    notificationPopupById = next;
  }

  function removePopupData(id) {
    const next = Object.assign({}, notificationPopupById);
    delete next[String(id)];
    notificationPopupById = next;
  }

  function popupData(id) {
    return notificationPopupById[String(id)] || {};
  }

  function addPopup(item) {
    const popup = Object.assign({ popupTime: Date.now(), pausedMs: 0 }, item);
    const existing = popupIndex(popup.id);
    if (existing >= 0)
      notificationPopupModel.remove(existing);

    setPopupData(popup);
    notificationPopupModel.insert(0, { popupId: popup.id });

    while (notificationPopupModel.count > 4) {
      let staleIndex = -1;
      for (let i = notificationPopupModel.count - 1; i >= 0; i--) {
        const candidate = popupData(notificationPopupModel.get(i).popupId);
        if (!notificationPopupPersistent(itemNotification(candidate))) {
          staleIndex = i;
          break;
        }
      }

      if (staleIndex < 0)
        break;

      const staleId = notificationPopupModel.get(staleIndex).popupId;
      hidePopup(staleId);
    }
  }

  function hidePopup(id, expireTransient) {
    const popup = popupData(id);
    const index = popupIndex(id);
    if (index >= 0)
      notificationPopupModel.remove(index);
    removePopupData(id);

    if (expireTransient !== false && popup?.notification?.transient)
      popup.notification.expire();
  }

  function expireNotificationPopups() {
    const popupIds = [];
    for (let i = 0; i < notificationPopupModel.count; i++)
      popupIds.push(notificationPopupModel.get(i).popupId);

    for (let i = 0; i < popupIds.length; i++)
      hidePopup(popupIds[i]);
  }

  function patchPopup(id, patch) {
    const current = popupData(id);
    if (current.id !== undefined)
      setPopupData(Object.assign({}, current, patch));
  }

  function setFocusMode(enabled) {
    focusMode = enabled;
    focusFile.setText(enabled ? "1" : "0");
    focusProc.exec([backend, "focus", enabled ? "on" : "off"]);
    if (!enabled)
      focusBarOpen = false;
  }

  function toggleOpen() {
    open = !open;
  }

  function boundedBackendCommand(args, timeoutSeconds) {
    const seconds = timeoutSeconds || backendQueryTimeout;
    return ["timeout", "--kill-after=1s", String(seconds) + "s", backend].concat(args);
  }

  function invalidateBluetoothSnapshot(includeDevices) {
    bluetoothStatusReady = false;
    bluetoothAvailable = false;
    bluetoothEnabled = false;
    bluetoothDiscoverable = false;
    bluetoothPairable = false;
    bluetoothDiscovering = false;
    if (includeDevices) {
      bluetoothDevicesReady = false;
      bluetoothDevices = [];
    }
  }

  function invalidateBluetoothForPage() {
    if (page === "main" || page === "bluetooth") {
      bluetoothGeneration++;
      invalidateBluetoothSnapshot(true);
    }
  }

  function requestBluetoothRefresh(process) {
    if (process.running) {
      process.refreshPending = true;
      return;
    }
    process.refreshPending = false;
    process.output = "";
    process.generation = bluetoothGeneration;
    process.running = true;
  }

  function finishBluetoothRefresh(process, relevant) {
    const rerun = process.refreshPending && open && relevant;
    process.refreshPending = false;
    if (rerun)
      Qt.callLater(function() { root.requestBluetoothRefresh(process); });
  }

  function refreshBluetoothForPage() {
    if (!open)
      return;
    if (page === "main" || page === "bluetooth")
      refreshBluetooth(true);
  }

  function handleBluetoothGap() {
    if (page === "bluetooth")
      endBluetoothSession();
    invalidateBluetoothForPage();
  }

  function refreshAll() {
    refreshBluetoothForPage();
    if (brightnessSupported)
      brightnessProc.running = true;
    metricsProc.running = true;
    powerProc.running = true;
  }

  function refreshBluetooth(includeDevices) {
    requestBluetoothRefresh(bluetoothStatusProc);
    if (includeDevices !== false)
      requestBluetoothRefresh(bluetoothDevicesProc);
  }

  function beginBluetoothSession() {
    if (!open || page !== "bluetooth" || !bluetoothAvailable || !bluetoothEnabled || bluetoothOperation === "disable")
      return;
    if (bluetoothSessionActive || bluetoothSessionProc.running)
      return;

    bluetoothError = "";
    bluetoothSessionClosing = false;
    bluetoothSessionProc.output = "";
    bluetoothSessionProc.exec([backend, "bluetooth", "session"]);
  }

  function endBluetoothSession() {
    bluetoothSessionActive = false;
    bluetoothDiscoveryRestartTimer.stop();
    stopBluetoothDiscovery();
    if (bluetoothSessionProc.running) {
      bluetoothSessionClosing = true;
      bluetoothSessionProc.write("close\n");
      bluetoothSessionStopTimer.restart();
    } else {
      bluetoothSessionClosing = false;
    }
  }

  function stopBluetoothDiscovery() {
    if (!bluetoothDiscoveryProc.running)
      return;
    if (bluetoothDiscoveryStopRequested)
      return;

    bluetoothDiscoveryStopRequested = true;
    bluetoothDiscoveryStopTimer.restart();
    if (bluetoothDiscoveryStarted)
      bluetoothDiscoveryProc.write("scan off\n");
  }

  function startBluetoothDiscovery() {
    if (bluetoothDiscoveryProc.running)
      return;

    bluetoothDiscoveryStarted = false;
    bluetoothDiscoveryStopRequested = false;
    bluetoothDiscoveryStopTimer.stop();
    bluetoothDiscoveryProc.running = true;
  }

  function restartBluetoothDiscovery() {
    if (!bluetoothSessionActive)
      return;
    if (bluetoothDiscoveryProc.running)
      stopBluetoothDiscovery();
    else
      bluetoothDiscoveryRestartTimer.restart();
    bluetoothDevicesReady = false;
    refreshBluetooth();
  }

  function setBrightness(value) {
    if (!brightnessSupported || !brightnessWritable)
      return;
    const percent = Math.round(clamp(value, 0, 1) * 100);
    if (brightnessBackend === "ddc") {
      pendingBrightnessPercent = percent;
      brightnessSetTimer.restart();
    } else {
      setBrightnessProc.exec([backend, "brightness", "set", String(percent)]);
    }
    brightness = percent / 100;
    showOsd("brightness", brightness);
  }

  function setPowerProfile(profile) {
    if (!profile)
      return;
    setPowerProc.exec([backend, "power", "set", profile]);
    power.profile = profile;
    powerProc.running = true;
  }

  function connectWifi(network, password) {
    if (!network || network.stateChanging || !wifiEnabled)
      return;
    wifiError = "";
    connectionTargetSsid = String(network.name || "");
    wifi.connectNetwork(network, password || "");
  }

  function requestWifiPassword(network) {
    const ssid = String(network?.name || "");
    if (pendingSsid !== ssid)
      pendingPassword = "";
    pendingSsid = ssid;
    connectionTargetSsid = ssid;
  }

  function disconnectWifi(network) {
    if (!network || network.stateChanging || !network.connected)
      return;
    wifiError = "";
    pendingSsid = "";
    pendingPassword = "";
    connectionTargetSsid = "";
    wifi.disconnectNetwork(network);
  }

  function toggleWifi() {
    if (!wifi.backendAvailable || !wifi.hardwareEnabled)
      return;
    wifiError = "";
    pendingSsid = "";
    pendingPassword = "";
    connectionTargetSsid = "";
    wifi.setEnabled(!wifiEnabled);
  }

  function scanWifi() {
    if (!wifiAdapterAvailable())
      return;
    wifiError = "";
    wifi.requestScan();
  }

  function toggleBluetooth() {
    if (bluetoothBusy || !bluetoothAvailable)
      return;
    bluetoothError = "";
    bluetoothOperation = bluetoothEnabled ? "disable" : "enable";
    bluetoothOperationAddress = "";
    bluetoothOperationName = "";
    if (bluetoothEnabled)
      endBluetoothSession();
    else
      bluetoothDevicesReady = false;
    bluetoothToggleProc.output = "";
    bluetoothToggleProc.exec(boundedBackendCommand(["bluetooth", bluetoothEnabled ? "off" : "on"], 15));
  }

  function runBluetoothDeviceAction(device) {
    if (bluetoothBusy || !bluetoothEnabled || !device?.address)
      return;

    bluetoothError = "";
    bluetoothOperation = device.connected ? "disconnect" : (device.paired ? "connect" : "pair");
    bluetoothOperationAddress = String(device.address);
    bluetoothOperationName = String(device.name || device.address);
    bluetoothActionProc.output = "";
    bluetoothActionProc.exec(boundedBackendCommand(["bluetooth", bluetoothOperation, bluetoothOperationAddress], 35));
  }

  function forgetBluetoothDevice(device) {
    if (bluetoothBusy || !bluetoothEnabled || !device?.paired || !device?.address)
      return;

    bluetoothError = "";
    bluetoothOperation = "remove";
    bluetoothOperationAddress = String(device.address);
    bluetoothOperationName = String(device.name || device.address);
    bluetoothActionProc.output = "";
    bluetoothActionProc.exec(boundedBackendCommand(["bluetooth", "remove", bluetoothOperationAddress], 20));
  }

  function requestForgetBluetoothDevice(device) {
    if (bluetoothBusy || !bluetoothEnabled || !device?.paired || !device?.address)
      return;

    const address = String(device.address);
    if (pendingBluetoothForgetAddress === address) {
      pendingBluetoothForgetAddress = "";
      bluetoothForgetTimer.stop();
      forgetBluetoothDevice(device);
      return;
    }

    pendingBluetoothForgetAddress = address;
    bluetoothForgetTimer.restart();
  }

  function finishBluetoothOperation(exitCode, output, fallbackError) {
    if (exitCode !== 0)
      bluetoothError = cleanBluetoothError(output, fallbackError);
    bluetoothOperation = "";
    bluetoothOperationAddress = "";
    bluetoothOperationName = "";
    pendingBluetoothForgetAddress = "";
    bluetoothForgetTimer.stop();
    refreshBluetooth();
    bluetoothSettleTimer.restart();
  }

  function parseJson(text, fallback) {
    try {
      return JSON.parse(text);
    } catch (error) {
      console.error("control-center: JSON parse failed: " + error);
      return fallback;
    }
  }

  Component.onCompleted: {
    dnd = dndFile.text().trim() === "1";
    focusMode = focusFile.text().trim() === "1";
    updateNotificationCount();
    refreshAll();
    focusProc.exec([backend, "focus", "restore"]);
  }

  onPageChanged: {
    if (page !== "wifi") {
      pendingSsid = "";
      pendingPassword = "";
      connectionTargetSsid = "";
    }
    if (page !== "bluetooth")
      endBluetoothSession();
    if (open) {
      invalidateBluetoothForPage();
      refreshBluetoothForPage();
    }
    if (page === "bluetooth" && open)
      beginBluetoothSession();

    if (!open || !mainSurfaceTransition.presented) {
      pageTransition.stop();
      displayedPage = page;
      pageLoader.opacity = 1;
      pageLoader.x = 0;
    } else {
      pageDirection = page === "main" ? -1 : 1;
      pageTransition.restart();
    }
  }

  onOpenChanged: {
    if (open) {
      notificationTimelineNow = Date.now();
      lastBluetoothPollAt = Date.now();
      invalidateBluetoothForPage();
      refreshAll();
    } else {
      lastBluetoothPollAt = 0;
      pendingSsid = "";
      pendingPassword = "";
      connectionTargetSsid = "";
    }
    if (focusMode && open) {
      focusBarOpen = true;
      barProc.exec([backend, "bar", "show"]);
    } else if (focusMode && focusBarOpen) {
      focusHideTimer.restart();
    }
    if (open && page === "bluetooth")
      beginBluetoothSession();
    else if (!open)
      endBluetoothSession();
  }

  Timer {
    interval: root.bluetoothPollInterval
    running: root.open
    repeat: true
    onTriggered: {
      const now = Date.now();
      if ((root.page === "main" || root.page === "bluetooth")
          && root.lastBluetoothPollAt > 0
          && now - root.lastBluetoothPollAt > root.bluetoothStaleAfter)
        root.handleBluetoothGap();
      root.lastBluetoothPollAt = now;
      root.refreshAll();
    }
  }

  Timer {
    id: bluetoothSettleTimer
    interval: 900
    repeat: false
    onTriggered: root.refreshBluetooth()
  }

  Timer {
    id: bluetoothSessionStopTimer
    interval: 1200
    repeat: false
    onTriggered: {
      if (bluetoothSessionProc.running)
        bluetoothSessionProc.running = false;
    }
  }

  Timer {
    id: bluetoothDiscoveryRestartTimer
    interval: 350
    repeat: false
    onTriggered: {
      if (root.bluetoothSessionActive && root.open && root.page === "bluetooth")
        root.startBluetoothDiscovery();
    }
  }

  Timer {
    id: bluetoothDiscoveryStopTimer
    interval: 1500
    repeat: false
    onTriggered: {
      if (bluetoothDiscoveryProc.running)
        bluetoothDiscoveryProc.running = false;
    }
  }

  Timer {
    id: bluetoothForgetTimer
    interval: 4000
    repeat: false
    onTriggered: root.pendingBluetoothForgetAddress = ""
  }

  Timer {
    interval: 1000
    running: root.open && root.notifications.length > 0
    repeat: true
    onTriggered: root.notificationTimelineNow = Date.now()
  }

  Timer {
    id: clearUndoTimer
    interval: root.clearUndoTimeout
    repeat: false
    onTriggered: root.finalizeClearNotifications()
  }

  ListModel {
    id: osdModel
  }

  Timer {
    id: osdSweepTimer
    onTriggered: root.sweepOsd()
  }

  ListModel {
    id: notificationPopupModel
  }

  FontMetrics {
    id: notificationActionFont
    font.family: theme.fontFamily
    font.pixelSize: 12
    font.bold: true
  }

  Timer {
    interval: 600
    running: true
    onTriggered: volumeReady = true
  }

  PwObjectTracker {
    objects: audioDetailsActive ? Pipewire.nodes.values : [sink]
  }

  Connections {
    target: sink?.audio ?? null
    function onVolumeChanged() {
      if (volumeReady)
        showOsd("volume", sink.audio.volume || 0);
    }
    function onMutedChanged() {
      if (volumeReady)
        showOsd("volume", sink?.audio?.muted ? 0 : (sink?.audio?.volume || 0));
    }
  }

  FileView {
    id: dndFile
    path: preferencesDir + "/dnd"
    preload: true
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.dnd = text().trim() === "1"
    onTextChanged: root.dnd = text().trim() === "1"
    onLoadFailed: function() { setText("0"); }
  }

  FileView {
    id: countFile
    path: stateDir + "/count"
    preload: true
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.updateNotificationCount()
    onLoadFailed: function() { setText("0"); }
  }

  FileView {
    id: focusFile
    path: preferencesDir + "/focus"
    preload: true
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.focusMode = text().trim() === "1"
    onTextChanged: root.focusMode = text().trim() === "1"
    onLoadFailed: function() { setText("0"); }
  }

  NotificationServer {
    id: notificationServer
    extraHints: ["sound"]
    actionIconsSupported: true
    actionsSupported: true
    bodyHyperlinksSupported: true
    bodyImagesSupported: false
    bodyMarkupSupported: true
    bodySupported: true
    imageSupported: true
    inlineReplySupported: true
    keepOnReload: false
    persistenceSupported: true

    onNotification: function(notification) {
      notification.tracked = true;
      const notificationId = Number(notification.id);
      const policy = root.notificationPolicy(notification);
      const item = {
        id: notificationId,
        notification: notification,
        time: Date.now()
      };
      notification.closed.connect(function() {
        root.removeNotification(notificationId, false);
      });

      // Transient notifications may be shown as popups, but must not become
      // persistent notification-center history.
      if (!notification.transient) {
        notifications = [item].concat(notifications);
        updateNotificationCount();
      }

      if (policy.sound)
        Quickshell.execDetached([backend, "sound", "notification"]);
      if (policy.popup) {
        addPopup(item);
      } else if (notification.transient) {
        notification.expire();
      }
    }
  }

  Process {
    id: bluetoothStatusProc
    property string output: ""
    property int generation: -1
    property bool refreshPending: false
    command: root.boundedBackendCommand(["bluetooth", "status-json"])
    stdout: StdioCollector {
      onStreamFinished: bluetoothStatusProc.output = text
    }
    onExited: function(exitCode) {
      if (exitCode === 0 && generation === root.bluetoothGeneration) {
        const data = parseJson(output, null);
        if (data && typeof data.available === "boolean" && typeof data.enabled === "boolean") {
          bluetoothAvailable = data.available;
          bluetoothEnabled = data.enabled;
          bluetoothDiscoverable = Boolean(data.discoverable);
          bluetoothPairable = Boolean(data.pairable);
          bluetoothDiscovering = Boolean(data.discovering);
          bluetoothStatusReady = true;
          if (!bluetoothEnabled) {
            bluetoothDevices = [];
            bluetoothDevicesReady = true;
            if (bluetoothSessionActive)
              endBluetoothSession();
          } else if (root.open && root.page === "bluetooth") {
            beginBluetoothSession();
          }
        }
      }
      root.finishBluetoothRefresh(bluetoothStatusProc, root.page === "main" || root.page === "bluetooth");
    }
  }

  Process {
    id: bluetoothDevicesProc
    property string output: ""
    property int generation: -1
    property bool refreshPending: false
    command: root.boundedBackendCommand(["bluetooth", "devices-json"])
    stdout: StdioCollector {
      onStreamFinished: bluetoothDevicesProc.output = text
    }
    onExited: function(exitCode) {
      if (exitCode === 0 && generation === root.bluetoothGeneration) {
        const data = parseJson(output, null);
        if (Array.isArray(data)) {
          bluetoothDevices = data;
          bluetoothDevicesReady = true;
        }
      }
      root.finishBluetoothRefresh(bluetoothDevicesProc, root.page === "main" || root.page === "bluetooth");
    }
  }

  Process {
    id: bluetoothSessionProc
    property string output: ""
    stdinEnabled: true
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function(data) {
        const line = String(data).trim();
        bluetoothSessionProc.output = (bluetoothSessionProc.output + "\n" + line).trim();
        if (line === "ready" && root.open && root.page === "bluetooth" && root.bluetoothEnabled) {
          root.bluetoothSessionActive = true;
          root.startBluetoothDiscovery();
          root.refreshBluetooth();
        }
      }
    }
    stderr: StdioCollector {
      onStreamFinished: bluetoothSessionProc.output = (bluetoothSessionProc.output + "\n" + text).trim()
    }
    onExited: function(exitCode) {
      const wasClosing = root.bluetoothSessionClosing;
      bluetoothSessionStopTimer.stop();
      root.bluetoothSessionClosing = false;
      root.bluetoothSessionActive = false;
      root.stopBluetoothDiscovery();

      if (!wasClosing && root.open && root.page === "bluetooth" && root.bluetoothEnabled)
        root.bluetoothError = root.cleanBluetoothError(output, "Pairing mode ended unexpectedly");
      else if (wasClosing && root.open && root.page === "bluetooth" && root.bluetoothEnabled)
        Qt.callLater(function() { root.beginBluetoothSession(); });
    }
  }

  Process {
    id: bluetoothDiscoveryProc
    command: [backend, "bluetooth", "discover"]
    stdinEnabled: true
    onStarted: bluetoothDiscoveryProc.write("scan on\n")
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function(data) {
        const line = String(data).replace(/\x1b\[[0-9;]*m/g, "").trim();
        if (line.includes("Discovery started")) {
          root.bluetoothDiscoveryStarted = true;
          if (root.bluetoothDiscoveryStopRequested)
            bluetoothDiscoveryProc.write("scan off\n");
        } else if (line.includes("Discovery stopped")) {
          root.bluetoothDiscoveryStarted = false;
          bluetoothDiscoveryProc.write("quit\n");
        } else if (line.includes("Failed to start discovery") || line.includes("Failed to stop discovery")) {
          root.bluetoothError = root.cleanBluetoothError(line, "Bluetooth discovery failed");
          bluetoothDiscoveryProc.write("quit\n");
        }
      }
    }
    onExited: {
      bluetoothDiscoveryStopTimer.stop();
      root.bluetoothDiscoveryStarted = false;
      root.bluetoothDiscoveryStopRequested = false;
      if (root.bluetoothSessionActive && root.open && root.page === "bluetooth")
        bluetoothDiscoveryRestartTimer.restart();
    }
  }

  Process {
    id: bluetoothToggleProc
    property string output: ""
    stdout: StdioCollector {
      onStreamFinished: bluetoothToggleProc.output = (bluetoothToggleProc.output + "\n" + text).trim()
    }
    stderr: StdioCollector {
      onStreamFinished: bluetoothToggleProc.output = (bluetoothToggleProc.output + "\n" + text).trim()
    }
    onExited: function(exitCode) {
      root.finishBluetoothOperation(exitCode, output, "Could not change Bluetooth state");
    }
  }

  Process {
    id: bluetoothActionProc
    property string output: ""
    stdout: StdioCollector {
      onStreamFinished: bluetoothActionProc.output = (bluetoothActionProc.output + "\n" + text).trim()
    }
    stderr: StdioCollector {
      onStreamFinished: bluetoothActionProc.output = (bluetoothActionProc.output + "\n" + text).trim()
    }
    onExited: function(exitCode) {
      const action = root.bluetoothOperation;
      const fallback = action === "pair"
        ? "Could not pair with this device"
        : (action === "connect"
            ? "Could not connect to this device"
            : (action === "disconnect"
                ? "Could not disconnect this device"
                : "Could not forget this device"));
      root.finishBluetoothOperation(exitCode, output, fallback);
    }
  }

  Process {
    id: brightnessProc
    command: [backend, "brightness", "get"]
    stdout: StdioCollector {
      onStreamFinished: {
        const nextValue = clamp(Number(text.trim()) / 100, 0, 1);
        if (brightnessReady && Math.abs(nextValue - brightness) > 0.005)
          showOsd("brightness", nextValue);
        brightness = nextValue;
        brightnessReady = true;
      }
    }
  }

  Process {
    id: brightnessBackendProc
    command: [backend, "brightness", "capabilities-json"]
    running: true
    stdout: StdioCollector {
      onStreamFinished: {
        const capabilities = root.parseJson(text, {
          supported: false,
          backend: "",
          writable: false
        });
        root.brightnessSupported = Boolean(capabilities.supported);
        root.brightnessWritable = Boolean(capabilities.writable);
        if (capabilities.backend === "backlight" || capabilities.backend === "ddc")
          root.brightnessBackend = capabilities.backend;
        if (root.brightnessSupported) {
          brightnessProc.running = true;
          brightnessWatchProc.running = true;
        }
      }
    }
  }

  Process {
    id: brightnessWatchProc
    command: [backend, "brightness", "watch"]
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function(data) {
        const raw = String(data).trim();
        if (raw.length === 0)
          return;
        const nextValue = clamp(Number(raw) / 100, 0, 1);
        if (brightnessReady && Math.abs(nextValue - brightness) > 0.005)
          showOsd("brightness", nextValue);
        brightness = nextValue;
        brightnessReady = true;
      }
    }
    onExited: function(exitCode) {
      if (root.brightnessSupported && exitCode !== 3)
        brightnessWatchRestartTimer.restart();
    }
  }

  Timer {
    id: brightnessWatchRestartTimer
    interval: 1000
    onTriggered: {
      if (root.brightnessSupported)
        brightnessWatchProc.running = true;
    }
  }

  Process {
    id: setBrightnessProc
  }

  Timer {
    id: brightnessSetTimer
    interval: 250
    onTriggered: {
      if (setBrightnessProc.running) {
        restart();
        return;
      }
      setBrightnessProc.exec([
        backend,
        "brightness",
        "set",
        String(pendingBrightnessPercent)
      ]);
    }
  }

  Process {
    id: metricsProc
    command: [backend, "metrics"]
    stdout: StdioCollector {
      onStreamFinished: metrics = parseJson(text, metrics)
    }
  }

  Process {
    id: powerProc
    command: [backend, "power", "status-json"]
    stdout: StdioCollector {
      onStreamFinished: power = parseJson(text, power)
    }
  }

  Process {
    id: setPowerProc
    onExited: powerProc.running = true
  }

  Process {
    id: focusProc
  }

  Process {
    id: barProc
  }

  Process {
    id: cursorProc
    stdout: StdioCollector {
      onStreamFinished: {
        if (text.trim() === "yes") {
          focusHideTimer.restart();
        } else if (!root.open) {
          root.focusBarOpen = false;
          barProc.exec([backend, "bar", "hide"]);
        }
      }
    }
  }

  IpcHandler {
    target: "controlCenter"
    function toggle() { root.toggleOpen(); }
    function open() {
      if (root.open)
        root.refreshAll();
      else
        root.open = true;
    }
    function wifiPage() {
      const refresh = root.open && root.page === "wifi";
      root.page = "wifi";
      root.open = true;
      if (refresh)
        root.scanWifi();
    }
    function bluetoothPage() {
      const refresh = root.open && root.page === "bluetooth";
      root.page = "bluetooth";
      root.open = true;
      if (refresh)
        root.refreshBluetooth(true);
    }
    function close() { root.open = false; }
    function dnd() {
      root.dnd = !root.dnd;
      dndFile.setText(root.dnd ? "1" : "0");
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "custom" && event.data === "desktop-shell:dismiss-notification-popups")
        root.expireNotificationPopups();
      else if (event.name === "custom" && event.data === "desktop-shell:dismiss-shell-popup")
        root.open = false;
    }
  }

  PanelWindow {
    id: mainWindow
    screen: shellConfig.screen
    visible: mainSurfaceTransition.presented
    color: "transparent"
    exclusiveZone: 0
    WlrLayershell.namespace: "quickshell:controlCenter"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.open
      ? WlrKeyboardFocus.OnDemand
      : WlrKeyboardFocus.None

    mask: Region {
      item: root.open ? panel : null
    }

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

      Rectangle {
        anchors.fill: parent
        color: theme.surfaceScrim
        opacity: mainSurfaceTransition.progress

      Rectangle {
        id: panel
        width: Math.min(436, parent.width)
        height: parent.height
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        color: theme.surfaceGlassStrong
        border.color: "transparent"
        border.width: 0
        radius: 0
        clip: true

        transform: Translate {
          x: (1 - mainSurfaceTransition.progress) * 48
        }
        opacity: 0.42 + mainSurfaceTransition.progress * 0.58

        Rectangle {
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          width: 1
          color: Qt.alpha(theme.blue, 0.42)
        }

        MouseArea {
          anchors.fill: parent
          onClicked: function(mouse) { mouse.accepted = true; }
        }

        ColumnLayout {
          anchors.fill: parent
          anchors.leftMargin: 20
          anchors.rightMargin: 20
          anchors.topMargin: 14
          anchors.bottomMargin: 16
          spacing: 12
          opacity: Math.max(0, Math.min(1, (mainSurfaceTransition.progress - 0.12) / 0.88))
          transform: Translate {
            x: (1 - mainSurfaceTransition.progress) * 10
          }

          ControlHeader {
            Layout.fillWidth: true
            pageTitle: root.displayedPage === "wifi" ? "Wi-Fi" : (root.displayedPage === "bluetooth" ? "Bluetooth" : "Control")
            backVisible: root.displayedPage !== "main"
            onBack: root.page = "main"
          }

          Loader {
            id: pageLoader
            Layout.fillWidth: true
            Layout.fillHeight: true
            sourceComponent: root.displayedPage === "wifi" ? wifiPage : (root.displayedPage === "bluetooth" ? bluetoothPage : mainPage)
          }
        }
      }
    }

    Shortcut {
      sequence: "Esc"
      onActivated: root.open = false
    }
  }

  PanelWindow {
    id: osdWindow
    screen: shellConfig.screen
    visible: osdSurfaceTransition.presented
    color: "transparent"
    exclusiveZone: 0
    WlrLayershell.namespace: "quickshell:controlCenterOsd"
    WlrLayershell.layer: WlrLayer.Overlay
    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }
    mask: Region {
      item: osdBox
    }

    Rectangle {
      id: osdBox
      width: 276
      height: root.osdBoxHeight
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: parent.height * 0.26
      radius: 14
      color: theme.surfaceGlassStrong
      border.color: theme.borderSubtle
      border.width: 1
      opacity: osdSurfaceTransition.progress
      scale: 0.96 + osdSurfaceTransition.progress * 0.04
      transform: Translate {
        y: (1 - osdSurfaceTransition.progress) * 18
      }
      Behavior on height {
        MotionNumberAnimation { role: MotionNumberAnimation.Content }
      }

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: root.osdRowSpacing

        Repeater {
          model: osdModel
          delegate: OsdRow {
            required property string kind
            required property real osdLevel
            required property string displayText
            Layout.fillWidth: true
            Layout.preferredHeight: root.osdRowHeight
            icon: root.osdIcon(kind)
            level: osdLevel
            label: displayText
            accent: root.osdAccent(kind)
          }
        }
      }
    }
  }

  PanelWindow {
    id: popupWindow
    screen: shellConfig.screen
    visible: popupSurfaceTransition.presented
    color: "transparent"
    exclusiveZone: 0
    WlrLayershell.namespace: "quickshell:notificationPopups"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: popupKeyboardHover.hovered
      ? WlrKeyboardFocus.OnDemand
      : WlrKeyboardFocus.None

    anchors {
      top: true
      right: true
    }

    implicitWidth: popupColumn.width + 24
    implicitHeight: popupColumn.implicitHeight + 28
    mask: Region {
      item: popupColumn
    }

    ColumnLayout {
      id: popupColumn
      width: root.notificationPopupWidth()
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.margins: 14
      spacing: 10
      opacity: popupSurfaceTransition.progress
      transform: Translate {
        x: (1 - popupSurfaceTransition.progress) * 32
      }

      HoverHandler {
        id: popupKeyboardHover
      }

      Repeater {
        model: notificationPopupModel
        delegate: NotificationToast {
          required property var popupId
          item: root.popupData(popupId)
          onDismiss: root.dismissNotification(popupId)
          onHide: root.hidePopup(popupId)
        }
      }
    }
  }

  PanelWindow {
    id: focusWindow
    screen: shellConfig.screen
    visible: root.focusMode
    color: "transparent"
    WlrLayershell.namespace: "quickshell:focusBar"
    WlrLayershell.layer: WlrLayer.Top
    exclusiveZone: 0
    implicitHeight: 8
    anchors {
      top: true
      left: true
      right: true
    }
    mask: Region {
      item: focusHitbox
    }

    Item {
      id: focusHitbox
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      height: 8
    }

    MouseArea {
      id: focusHover
      anchors.fill: focusHitbox
      hoverEnabled: true
      onEntered: {
        root.focusBarOpen = true;
        barProc.exec([backend, "bar", "show"]);
        focusHideTimer.stop();
      }
      onExited: focusHideTimer.restart()
    }

    Timer {
      id: focusHideTimer
      interval: 1800
      onTriggered: {
        if (!focusHover.containsMouse && !root.open)
          cursorProc.exec([backend, "cursor", "near-top"]);
      }
    }

    Rectangle {
      id: focusEdge
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      height: root.focusBarOpen ? 2 : 4
      color: theme.blue
      opacity: root.focusBarOpen ? 0.35 : 0.8

      Behavior on height {
        MotionNumberAnimation { role: MotionNumberAnimation.FocusTravel }
      }
      Behavior on opacity {
        MotionNumberAnimation { role: MotionNumberAnimation.Feedback }
      }
    }
  }

  Component {
    id: mainPage
    Flickable {
      id: mainScroll
      clip: true
      contentWidth: width
      contentHeight: mainContent.implicitHeight
      boundsBehavior: Flickable.StopAtBounds
      ScrollBar.vertical: ThemedScrollBar {
        parent: mainScroll
        anchors.top: mainScroll.top
        anchors.right: mainScroll.right
        anchors.bottom: mainScroll.bottom
      }

      ColumnLayout {
        id: mainContent
        width: mainScroll.width
        spacing: 12

        Rectangle {
          id: commandCluster
          Layout.fillWidth: true
          implicitHeight: 118
          radius: 12
          color: theme.surfaceGlass
          border.color: Qt.alpha(theme.borderSubtle, 0.54)
          border.width: 1
          clip: true

          GridLayout {
            anchors.fill: parent
            anchors.margins: 7
            columns: 2
            rows: 2
            columnSpacing: 6
            rowSpacing: 4

            CommandButton {
              Layout.fillWidth: true
              icon: root.wifiEnabled ? "" : "󰤮"
              title: "Wi-Fi"
              subtitle: root.wifiSummaryText()
              active: root.wifiConnected
              accent: theme.blue
              onClicked: root.page = "wifi"
            }

            CommandButton {
              Layout.fillWidth: true
              icon: root.bluetoothEnabled ? "󰂯" : "󰂲"
              title: "Bluetooth"
              subtitle: root.bluetoothSummaryText()
              active: root.bluetoothConnectedDevices().length > 0
              accent: theme.purple
              onClicked: root.page = "bluetooth"
            }

            CommandButton {
              Layout.fillWidth: true
              icon: root.dnd ? "" : ""
              title: root.dnd ? "Silent" : "Notify"
              subtitle: root.dnd ? "DND" : "Live"
              active: root.dnd
              accent: theme.purple
              onClicked: {
                root.dnd = !root.dnd;
                dndFile.setText(root.dnd ? "1" : "0");
              }
            }

            CommandButton {
              Layout.fillWidth: true
              icon: "󰈈"
              title: "Focus"
              subtitle: root.focusMode ? "On" : "Off"
              active: root.focusMode
              accent: theme.green
              onClicked: root.setFocusMode(!root.focusMode)
            }
          }
        }

        Section {
          title: "Audio"

          Rectangle {
            Layout.fillWidth: true
            implicitHeight: audioMixerContent.implicitHeight + 22
            radius: 10
            color: Qt.alpha(theme.surfaceAccent, 0.72)
            border.color: Qt.alpha(theme.borderSubtle, 0.64)
            border.width: 1

            ColumnLayout {
              id: audioMixerContent
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: 12
              spacing: 2

              AudioDeviceSection {
                title: "Output"
                icon: sink?.audio?.muted ? "󰝟" : ""
                current: root.sink
                devices: root.outputDevices
                expanded: root.outputExpanded
                showDivider: false
                accent: theme.blue
                onToggleExpanded: root.outputExpanded = !root.outputExpanded
                onVolumeChanged: function(value) { root.setNodeVolume(root.sink, value); }
                onToggleMute: root.toggleNodeMute(root.sink)
                onChoose: function(node) {
                  Pipewire.preferredDefaultAudioSink = node;
                  root.outputExpanded = false;
                }
              }

              AudioDeviceSection {
                title: "Input"
                icon: source?.audio?.muted ? "" : ""
                current: root.source
                devices: root.inputDevices
                expanded: root.inputExpanded
                accent: theme.purple
                onToggleExpanded: root.inputExpanded = !root.inputExpanded
                onVolumeChanged: function(value) { root.setNodeVolume(root.source, value); }
                onToggleMute: root.toggleNodeMute(root.source)
                onChoose: function(node) {
                  Pipewire.preferredDefaultAudioSource = node;
                  root.inputExpanded = false;
                }
              }

              RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 10
                visible: root.appStreams.length > 0
                spacing: 9

                Text {
                  text: "Applications"
                  color: theme.terminalBlue
                  font.family: theme.fontFamily
                  font.pixelSize: 10
                  font.bold: true
                }
                Rectangle {
                  Layout.fillWidth: true
                  Layout.preferredHeight: 1
                  color: theme.borderSubtle
                  opacity: 0.62
                }
              }

              Repeater {
                model: root.appStreams
                delegate: StreamVolumeRow {
                  required property var modelData
                  required property int index
                  node: modelData
                  showDivider: index > 0
                }
              }
            }
          }
        }

        Section {
          title: "Display"
          visible: root.brightnessSupported

          Rectangle {
            Layout.fillWidth: true
            implicitHeight: displayControls.implicitHeight + 22
            radius: 10
            color: Qt.alpha(theme.surfaceAccent, 0.72)
            border.color: Qt.alpha(theme.borderSubtle, 0.64)
            border.width: 1

            ColumnLayout {
              id: displayControls
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: 12

              MetricCard {
                icon: "󰃠"
                title: "Brightness"
                subtitle: "Display backlight"
                value: root.brightness
                enabled: root.brightnessWritable
                showDivider: false
                accent: theme.yellow
                onChanged: function(value) { root.setBrightness(value); }
              }
            }
          }
        }

        Section {
          title: "Power profile"
          visible: false
          RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Repeater {
              model: root.power.choices || []
              delegate: PillButton {
                required property string modelData
                Layout.fillWidth: true
                icon: root.powerIcon(modelData)
                label: modelData
                active: root.power.profile === modelData
                onClicked: root.setPowerProfile(modelData)
              }
            }
          }
        }

        Section {
          title: "Device load"
          visible: false
          RowLayout {
            Layout.fillWidth: true
            spacing: 10
            MiniGauge {
              Layout.fillWidth: true
              label: "CPU"
              value: root.metrics.cpu || 0
              textValue: Math.round((root.metrics.cpu || 0) * 100) + "%"
              accent: theme.green
            }
            MiniGauge {
              Layout.fillWidth: true
              label: "RAM"
              value: root.metrics.ram || 0
              textValue: root.metrics.ramText || "--"
              accent: theme.purple
            }
            MiniGauge {
              Layout.fillWidth: true
              visible: root.metrics.hasVram
              label: "VRAM"
              value: root.metrics.vram || 0
              textValue: root.metrics.vramText || "--"
              accent: theme.orange
            }
          }
        }

        Section {
          title: "Notifications"
          RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Text {
              Layout.fillWidth: true
              text: root.notifications.length === 0
                ? (root.clearedNotifications.length > 0 ? "History cleared" : "No notifications")
                : root.notifications.length + " notification" + (root.notifications.length === 1 ? "" : "s")
              color: theme.text
              font.family: theme.fontFamily
              font.pixelSize: 12
            }
            PillButton {
              visible: root.notifications.length > 0
              label: "Clear"
              onClicked: root.clearNotifications()
            }
          }

          Rectangle {
            Layout.fillWidth: true
            implicitHeight: 48
            visible: root.clearedNotifications.length > 0
            radius: 9
            color: Qt.alpha(theme.purple, 0.12)
            border.color: Qt.alpha(theme.purple, 0.42)
            border.width: 1

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: 12
              anchors.rightMargin: 8
              spacing: 10

              Text {
                text: "󰕌"
                color: theme.purple
                font.family: theme.fontFamily
                font.pixelSize: 15
              }

              Text {
                Layout.fillWidth: true
                text: root.clearedNotifications.length + " cleared"
                color: theme.text
                font.family: theme.fontFamily
                font.pixelSize: 11
                font.bold: true
              }

              PillButton {
                label: "Undo"
                active: true
                onClicked: root.undoClearNotifications()
              }
            }
          }

          Text {
            Layout.fillWidth: true
            visible: root.notificationGroups(true).length > 0
            text: "NEEDS ATTENTION"
            color: theme.red
            font.family: theme.fontFamily
            font.pixelSize: 10
            font.bold: true
            font.letterSpacing: 0.8
            Layout.topMargin: 2
          }

          Repeater {
            model: root.notificationGroups(true)
            delegate: NotificationGroup {
              required property var modelData
              group: modelData
            }
          }

          Text {
            Layout.fillWidth: true
            visible: root.notificationGroups(false).length > 0
            text: "RECENT"
            color: theme.mutedAlt
            font.family: theme.fontFamily
            font.pixelSize: 10
            font.bold: true
            font.letterSpacing: 0.8
            Layout.topMargin: root.notificationGroups(true).length > 0 ? 5 : 2
          }

          Repeater {
            model: root.notificationGroups(false)
            delegate: NotificationGroup {
              required property var modelData
              group: modelData
            }
          }
        }
      }
    }
  }

  Component {
    id: wifiPage
    ColumnLayout {
      spacing: 12

      Rectangle {
        Layout.fillWidth: true
        implicitHeight: 72
        radius: 12
        color: Qt.alpha(theme.surfaceGlass, 0.82)
        border.color: root.wifiConnected
          ? Qt.alpha(theme.blue, 0.46)
          : Qt.alpha(theme.borderSubtle, 0.52)
        border.width: 1

        RowLayout {
          anchors.fill: parent
          anchors.margins: 12
          spacing: 12

          Rectangle {
            Layout.preferredWidth: 40
            Layout.preferredHeight: 40
            radius: 12
            color: root.wifiConnected
              ? Qt.alpha(theme.blue, 0.16)
              : Qt.alpha(theme.surfaceMuted, 0.86)

            Text {
              anchors.centerIn: parent
              text: root.wifiEnabled ? "" : "󰤮"
              color: root.wifiConnected ? theme.blue : (root.wifiEnabled ? theme.foreground : theme.mutedAlt)
              font.family: theme.fontFamily
              font.pixelSize: 19
            }
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
              Layout.fillWidth: true
              text: root.wifiHeaderTitle()
              color: theme.foreground
              font.family: theme.fontFamily
              font.pixelSize: 14
              font.bold: true
              elide: Text.ElideRight
            }

            Text {
              Layout.fillWidth: true
              text: root.wifiHeaderSubtitle()
              color: root.wifiConnected ? theme.blue : theme.text
              font.family: theme.fontFamily
              font.pixelSize: 11
              elide: Text.ElideRight
            }
          }

          RadioSwitch {
            checked: root.wifiEnabled
            busy: false
            enabled: wifi.backendAvailable && wifi.hardwareEnabled && wifi.device !== null && !root.wifiBusy
            onToggled: root.toggleWifi()
          }
        }
      }

      Rectangle {
        Layout.fillWidth: true
        visible: root.wifiError.length > 0
        implicitHeight: wifiErrorRow.implicitHeight + 18
        radius: 9
        color: Qt.alpha(theme.red, 0.09)
        border.color: Qt.alpha(theme.red, 0.4)
        border.width: 1

        RowLayout {
          id: wifiErrorRow
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: 11
          anchors.rightMargin: 8
          spacing: 9

          Text {
            text: ""
            color: theme.red
            font.family: theme.fontFamily
            font.pixelSize: 13
          }

          Text {
            Layout.fillWidth: true
            text: root.wifiError
            color: theme.foreground
            font.family: theme.fontFamily
            font.pixelSize: 11
            wrapMode: Text.WordWrap
          }

          IconButton {
            icon: "×"
            tooltip: "Dismiss"
            onClicked: root.wifiError = ""
          }
        }
      }

      RowLayout {
        Layout.fillWidth: true
        visible: root.wifiAdapterAvailable()
        spacing: 8

        Text {
          text: "AVAILABLE NETWORKS"
          color: theme.mutedAlt
          font.family: theme.fontFamily
          font.pixelSize: 10
          font.bold: true
          font.letterSpacing: 0.8
        }

        Text {
          Layout.fillWidth: true
          text: root.wifiNetworks.length + " found · live"
          color: theme.mutedAlt
          font.family: theme.fontFamily
          font.pixelSize: 10
          horizontalAlignment: Text.AlignRight
        }

        IconButton {
          icon: ""
          tooltip: "Refresh networks"
          active: false
          enabled: !root.wifiBusy
          onClicked: root.scanWifi()
        }
      }

      Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        Flickable {
          id: wifiScroll
          anchors.fill: parent
          visible: root.wifiAdapterAvailable() && root.wifiNetworks.length > 0
          clip: true
          contentWidth: width
          contentHeight: wifiContent.implicitHeight
          boundsBehavior: Flickable.StopAtBounds
          ScrollBar.vertical: ThemedScrollBar {
            parent: wifiScroll
            anchors.top: wifiScroll.top
            anchors.right: wifiScroll.right
            anchors.bottom: wifiScroll.bottom
          }

          ColumnLayout {
            id: wifiContent
            width: wifiScroll.width
            spacing: 4

            Repeater {
              model: root.wifiNetworks
              delegate: WifiNetworkRow {
                required property var modelData
                network: modelData
              }
            }
          }
        }

        Rectangle {
          anchors.fill: parent
          visible: !wifiScroll.visible
          radius: 12
          color: Qt.alpha(theme.surfaceGlass, 0.48)
          border.color: Qt.alpha(theme.borderSubtle, 0.42)
          border.width: 1

          ColumnLayout {
            anchors.centerIn: parent
            width: Math.min(parent.width - 48, 300)
            spacing: 9

            Rectangle {
              Layout.alignment: Qt.AlignHCenter
              Layout.preferredWidth: 52
              Layout.preferredHeight: 52
              radius: 16
              color: Qt.alpha(root.wifiAdapterAvailable() ? theme.blue : theme.mutedAlt, 0.11)

              Text {
                anchors.centerIn: parent
                text: root.wifiAdapterAvailable() ? "󰤯" : "󰤮"
                color: root.wifiAdapterAvailable() ? theme.blue : theme.mutedAlt
                font.family: theme.fontFamily
                font.pixelSize: 23
              }
            }

            Text {
              Layout.fillWidth: true
              text: !wifi.backendAvailable
                ? "Network service unavailable"
                : (!wifi.hardwareEnabled || !wifi.device
                    ? "Wi-Fi is unavailable"
                    : (!root.wifiEnabled ? "Wi-Fi is off" : "Looking for networks"))
              color: theme.foreground
              font.family: theme.fontFamily
              font.pixelSize: 14
              font.bold: true
              horizontalAlignment: Text.AlignHCenter
            }

            Text {
              Layout.fillWidth: true
              text: !wifi.backendAvailable
                ? "NetworkManager did not provide a networking backend."
                : (!wifi.hardwareEnabled || !wifi.device
                    ? "No wireless adapter is ready."
                    : (!root.wifiEnabled
                        ? "Turn it on to discover nearby networks."
                        : "Nearby networks will appear automatically."))
              color: theme.text
              font.family: theme.fontFamily
              font.pixelSize: 11
              wrapMode: Text.WordWrap
              horizontalAlignment: Text.AlignHCenter
            }

            PillButton {
              Layout.alignment: Qt.AlignHCenter
              visible: wifi.backendAvailable
                && wifi.hardwareEnabled
                && wifi.device !== null
                && (!root.wifiEnabled || root.wifiAdapterAvailable())
              label: root.wifiEnabled ? "Refresh scan" : "Turn on Wi-Fi"
              icon: root.wifiEnabled ? "" : ""
              active: !root.wifiEnabled
              enabled: !root.wifiBusy
              onClicked: root.wifiEnabled ? root.scanWifi() : root.toggleWifi()
            }
          }
        }
      }
    }
  }

  Component {
    id: bluetoothPage
    ColumnLayout {
      spacing: 12

      Rectangle {
        Layout.fillWidth: true
        implicitHeight: 72
        radius: 12
        color: Qt.alpha(theme.surfaceGlass, 0.82)
        border.color: root.bluetoothConnectedDevices().length > 0
          ? Qt.alpha(theme.purple, 0.5)
          : Qt.alpha(theme.borderSubtle, 0.52)
        border.width: 1

        RowLayout {
          anchors.fill: parent
          anchors.margins: 12
          spacing: 12

          Rectangle {
            Layout.preferredWidth: 40
            Layout.preferredHeight: 40
            radius: 12
            color: root.bluetoothConnectedDevices().length > 0
              ? Qt.alpha(theme.purple, 0.17)
              : Qt.alpha(theme.surfaceMuted, 0.86)

            Text {
              anchors.centerIn: parent
              text: root.bluetoothEnabled ? "󰂯" : "󰂲"
              color: root.bluetoothConnectedDevices().length > 0
                ? theme.purple
                : (root.bluetoothEnabled ? theme.foreground : theme.mutedAlt)
              font.family: theme.fontFamily
              font.pixelSize: 20
            }
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
              Layout.fillWidth: true
              text: root.bluetoothHeaderTitle()
              color: theme.foreground
              font.family: theme.fontFamily
              font.pixelSize: 14
              font.bold: true
              elide: Text.ElideRight
            }

            Text {
              Layout.fillWidth: true
              text: root.bluetoothHeaderSubtitle()
              color: root.bluetoothDiscoverable ? theme.purple : theme.text
              font.family: theme.fontFamily
              font.pixelSize: 11
              elide: Text.ElideRight
            }
          }

          RadioSwitch {
            checked: root.bluetoothEnabled
            busy: root.bluetoothOperation === "enable" || root.bluetoothOperation === "disable"
            enabled: root.bluetoothStatusReady && root.bluetoothAvailable && !root.bluetoothBusy
            onToggled: root.toggleBluetooth()
          }
        }
      }

      Rectangle {
        Layout.fillWidth: true
        visible: root.bluetoothError.length > 0
        implicitHeight: bluetoothErrorRow.implicitHeight + 18
        radius: 9
        color: Qt.alpha(theme.red, 0.09)
        border.color: Qt.alpha(theme.red, 0.4)
        border.width: 1

        RowLayout {
          id: bluetoothErrorRow
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: 11
          anchors.rightMargin: 8
          spacing: 9

          Text {
            text: ""
            color: theme.red
            font.family: theme.fontFamily
            font.pixelSize: 13
          }

          Text {
            Layout.fillWidth: true
            text: root.bluetoothError
            color: theme.foreground
            font.family: theme.fontFamily
            font.pixelSize: 11
            wrapMode: Text.WordWrap
          }

          IconButton {
            icon: "×"
            tooltip: "Dismiss"
            onClicked: root.bluetoothError = ""
          }
        }
      }

      Rectangle {
        Layout.fillWidth: true
        implicitHeight: 62
        radius: 11
        color: Qt.alpha(root.bluetoothDiscoverable ? theme.purple : theme.green, 0.09)
        border.color: Qt.alpha(root.bluetoothDiscoverable ? theme.purple : theme.green, 0.32)
        border.width: 1

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: 12
          anchors.rightMargin: 12
          spacing: 10

          Rectangle {
            Layout.preferredWidth: 34
            Layout.preferredHeight: 34
            radius: 10
            color: Qt.alpha(root.bluetoothDiscoverable ? theme.purple : theme.green, 0.15)

            Text {
              anchors.centerIn: parent
              text: root.bluetoothDiscoverable ? "󰑐" : "󰌾"
              color: root.bluetoothDiscoverable ? theme.purple : theme.green
              font.family: theme.fontFamily
              font.pixelSize: 16
            }
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
              Layout.fillWidth: true
              text: root.bluetoothDiscoverable ? "Visible while this page is open" : "Not discoverable"
              color: theme.foreground
              font.family: theme.fontFamily
              font.pixelSize: 12
              font.bold: true
            }

            Text {
              Layout.fillWidth: true
              text: root.bluetoothDiscoverable
                ? "Nearby devices can find this computer and pair with it."
                : (root.bluetoothEnabled ? "Paired devices can still reconnect normally." : "The Bluetooth radio is off.")
              color: theme.text
              font.family: theme.fontFamily
              font.pixelSize: 10
              elide: Text.ElideRight
            }
          }

          StatusPill {
            icon: root.bluetoothDiscoverable ? "󰂞" : "󰒃"
            label: root.bluetoothDiscoverable ? "VISIBLE" : "HIDDEN"
            active: true
            accent: root.bluetoothDiscoverable ? theme.purple : theme.green
          }
        }
      }

      RowLayout {
        Layout.fillWidth: true
        visible: root.bluetoothEnabled && root.bluetoothAvailable
        spacing: 8

        Text {
          text: "DEVICES"
          color: theme.mutedAlt
          font.family: theme.fontFamily
          font.pixelSize: 10
          font.bold: true
          font.letterSpacing: 0.8
        }

        Text {
          Layout.fillWidth: true
          text: !root.bluetoothDevicesReady
            ? "Loading…"
            : root.bluetoothDevices.length + " found"
          color: root.bluetoothSessionActive ? theme.purple : theme.mutedAlt
          font.family: theme.fontFamily
          font.pixelSize: 10
          horizontalAlignment: Text.AlignRight
        }

        IconButton {
          icon: ""
          tooltip: "Scan again"
          active: root.bluetoothSessionActive
          enabled: root.bluetoothSessionActive && !root.bluetoothBusy
          onClicked: root.restartBluetoothDiscovery()
        }
      }

      Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        Flickable {
          id: bluetoothScroll
          anchors.fill: parent
          visible: root.bluetoothEnabled && root.bluetoothAvailable && root.bluetoothDevices.length > 0
          clip: true
          contentWidth: width
          contentHeight: bluetoothContent.implicitHeight
          boundsBehavior: Flickable.StopAtBounds
          ScrollBar.vertical: ThemedScrollBar {
            parent: bluetoothScroll
            anchors.top: bluetoothScroll.top
            anchors.right: bluetoothScroll.right
            anchors.bottom: bluetoothScroll.bottom
          }

          ColumnLayout {
            id: bluetoothContent
            width: bluetoothScroll.width
            spacing: 5

            Text {
              Layout.fillWidth: true
              visible: root.bluetoothPairedDevices().length > 0
              text: "MY DEVICES"
              color: theme.mutedAlt
              font.family: theme.fontFamily
              font.pixelSize: 9
              font.bold: true
              font.letterSpacing: 0.7
              Layout.topMargin: 2
            }

            Repeater {
              model: root.bluetoothPairedDevices()
              delegate: BluetoothDeviceRow {
                required property var modelData
                device: modelData
              }
            }

            Text {
              Layout.fillWidth: true
              visible: root.bluetoothNearbyDevices().length > 0
              text: "NEARBY"
              color: theme.mutedAlt
              font.family: theme.fontFamily
              font.pixelSize: 9
              font.bold: true
              font.letterSpacing: 0.7
              Layout.topMargin: root.bluetoothPairedDevices().length > 0 ? 7 : 2
            }

            Repeater {
              model: root.bluetoothNearbyDevices()
              delegate: BluetoothDeviceRow {
                required property var modelData
                device: modelData
              }
            }
          }
        }

        Rectangle {
          anchors.fill: parent
          visible: !bluetoothScroll.visible
          radius: 12
          color: Qt.alpha(theme.surfaceGlass, 0.48)
          border.color: Qt.alpha(theme.borderSubtle, 0.42)
          border.width: 1

          ColumnLayout {
            anchors.centerIn: parent
            width: Math.min(parent.width - 48, 310)
            spacing: 9

            Rectangle {
              Layout.alignment: Qt.AlignHCenter
              Layout.preferredWidth: 52
              Layout.preferredHeight: 52
              radius: 16
              color: Qt.alpha(root.bluetoothEnabled ? theme.purple : theme.mutedAlt, 0.11)

              Text {
                anchors.centerIn: parent
                text: !root.bluetoothStatusReady
                  ? "󰔟"
                  : (!root.bluetoothAvailable || !root.bluetoothEnabled
                      ? "󰂲"
                      : "󰂯")
                color: root.bluetoothEnabled ? theme.purple : theme.mutedAlt
                font.family: theme.fontFamily
                font.pixelSize: 23

                SequentialAnimation on opacity {
                  running: root.bluetoothEnabled && root.bluetoothSessionActive && !root.bluetoothDevicesReady
                  loops: Animation.Infinite
                  NumberAnimation { to: 0.3; duration: 440 }
                  NumberAnimation { to: 1; duration: 440 }
                }
              }
            }

            Text {
              Layout.fillWidth: true
              text: !root.bluetoothStatusReady
                ? "Checking Bluetooth"
                : (!root.bluetoothAvailable
                    ? "Bluetooth is unavailable"
                    : (!root.bluetoothEnabled
                        ? "Bluetooth is off"
                        : (!root.bluetoothDevicesReady
                            ? "Looking for devices"
                            : "No devices found")))
              color: theme.foreground
              font.family: theme.fontFamily
              font.pixelSize: 14
              font.bold: true
              horizontalAlignment: Text.AlignHCenter
            }

            Text {
              Layout.fillWidth: true
              text: !root.bluetoothStatusReady
                ? "Reading the current BlueZ state…"
                : (!root.bluetoothAvailable
                    ? "No controller is ready on this system."
                    : (!root.bluetoothEnabled
                        ? "Turn it on to reconnect paired devices or add a new one."
                        : "Put the accessory in pairing mode. It will appear here without leaving this screen."))
              color: theme.text
              font.family: theme.fontFamily
              font.pixelSize: 11
              wrapMode: Text.WordWrap
              horizontalAlignment: Text.AlignHCenter
            }

            PillButton {
              Layout.alignment: Qt.AlignHCenter
              visible: root.bluetoothStatusReady && root.bluetoothAvailable && !root.bluetoothBusy
              label: root.bluetoothEnabled ? "Scan again" : "Turn on Bluetooth"
              icon: root.bluetoothEnabled ? "" : "󰂯"
              active: !root.bluetoothEnabled
              enabled: !root.bluetoothBusy
              onClicked: root.bluetoothEnabled ? root.restartBluetoothDiscovery() : root.toggleBluetooth()
            }
          }
        }
      }
    }
  }

  component Section: ColumnLayout {
    property string title
    Layout.fillWidth: true
    spacing: 8
    Text {
      text: parent.title
      color: theme.terminalBlue
      font.family: theme.fontFamily
      font.pixelSize: 12
      font.bold: true
    }
  }

  component ThemedScrollBar: ScrollBar {
    id: scrollBar
    policy: ScrollBar.AsNeeded
    width: 6
    padding: 0
    opacity: scrollBar.active || scrollBar.hovered || scrollBar.pressed ? 1 : 0

    background: Rectangle {
      color: "transparent"
    }

    contentItem: Rectangle {
      implicitWidth: 4
      radius: 2
      color: theme.blue
      opacity: 0.72

    }

    Behavior on opacity {
      MotionNumberAnimation { role: MotionNumberAnimation.Feedback }
    }
  }

  component ControlHeader: Rectangle {
    id: header
    property string pageTitle
    property bool backVisible: false
    signal back

    implicitHeight: 54
    radius: 0
    color: "transparent"
    border.color: "transparent"
    border.width: 0

    ColumnLayout {
      anchors.fill: parent
      spacing: 8

      RowLayout {
        Layout.fillWidth: true
        spacing: 10

        IconButton {
          visible: header.backVisible
          icon: ""
          tooltip: "Back"
          onClicked: header.back()
        }

        Text {
          Layout.fillWidth: true
          text: header.pageTitle
          color: theme.foreground
          font.family: theme.fontFamily
          font.pixelSize: 22
          font.bold: true
          elide: Text.ElideRight
        }

        StatusPill {
          visible: root.notifications.length > 0 && !header.backVisible
          icon: ""
          label: String(root.notifications.length)
          active: true
          accent: theme.yellow
        }
      }

      Rectangle {
        Layout.fillWidth: true
        height: 1
        color: theme.borderSubtle
        opacity: 0.46
      }
    }
  }

  component StatusPill: Rectangle {
    id: pill
    property string icon
    property string label
    property bool active: false
    property color accent: theme.blue

    implicitWidth: pillRow.implicitWidth + 18
    implicitHeight: 26
    radius: 8
    color: active ? Qt.alpha(accent, 0.15) : "transparent"
    border.color: active ? Qt.alpha(accent, 0.48) : theme.borderSubtle
    border.width: 1

    RowLayout {
      id: pillRow
      anchors.centerIn: parent
      width: Math.min(parent.width - 12, implicitWidth)
      spacing: 6

      Text {
        text: pill.icon
        color: pill.active ? pill.accent : theme.mutedAlt
        font.family: theme.fontFamily
        font.pixelSize: 11
      }

      Text {
        Layout.fillWidth: true
        text: pill.label
        color: pill.active ? theme.foreground : theme.text
        font.family: theme.fontFamily
        font.pixelSize: 10
        font.bold: pill.active
        elide: Text.ElideRight
      }
    }
  }

  component CommandButton: Rectangle {
    id: command
    property string icon
    property string title
    property string subtitle
    property bool active: false
    property color accent: theme.blue
    signal clicked

    Layout.preferredHeight: 50
    radius: 9
    color: active ? Qt.alpha(accent, 0.13) : commandHover.containsMouse ? theme.surfaceAccent : "transparent"
    border.color: "transparent"
    border.width: 0
    scale: commandHover.pressed ? 0.97 : (commandHover.containsMouse ? 1.012 : 1)

    Behavior on color {
      MotionColorAnimation { role: MotionNumberAnimation.Feedback }
    }
    Behavior on scale {
      MotionNumberAnimation { role: MotionNumberAnimation.Feedback }
    }

    RowLayout {
      anchors.fill: parent
      anchors.leftMargin: 9
      anchors.rightMargin: 8
      spacing: 8

      Text {
        text: command.icon
        color: command.active ? command.accent : theme.foreground
        font.family: theme.fontFamily
        font.pixelSize: 17
        Layout.preferredWidth: 24
        horizontalAlignment: Text.AlignHCenter
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 1

        Text {
          Layout.fillWidth: true
          text: command.title
          color: theme.foreground
          font.family: theme.fontFamily
          font.pixelSize: 12
          font.bold: true
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          text: command.subtitle
          color: command.active ? command.accent : theme.text
          font.family: theme.fontFamily
          font.pixelSize: 10
          elide: Text.ElideRight
        }
      }

      Rectangle {
        Layout.preferredWidth: 6
        Layout.preferredHeight: 6
        radius: 3
        color: command.active ? command.accent : theme.borderSubtle
        opacity: command.active ? 1 : 0.5
      }
    }

    MouseArea {
      id: commandHover
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: command.clicked()
    }
  }

  component PillButton: Rectangle {
    id: btn
    property string label
    property string icon: ""
    property string iconSource: ""
    property bool active: false
    property real maximumWidth: -1
    signal clicked
    implicitHeight: 34
    implicitWidth: {
      const naturalWidth = Math.max(72, contentRow.implicitWidth + 22);
      return maximumWidth > 0 ? Math.min(maximumWidth, naturalWidth) : naturalWidth;
    }
    radius: 8
    color: active ? theme.terminalBlue : (btnMouse.containsMouse ? theme.surfaceAccent : theme.surfaceMuted)
    border.color: active ? theme.blue : (btnMouse.containsMouse ? theme.borderSubtle : theme.borderMuted)
    border.width: 1
    opacity: enabled ? 1 : 0.46
    scale: btnMouse.pressed ? 0.94 : (btnMouse.containsMouse ? 1.025 : 1)

    Behavior on color {
      MotionColorAnimation { role: MotionNumberAnimation.Feedback }
    }
    Behavior on border.color {
      MotionColorAnimation { role: MotionNumberAnimation.Feedback }
    }
    Behavior on scale {
      MotionNumberAnimation { role: MotionNumberAnimation.Feedback }
    }

    RowLayout {
      id: contentRow
      anchors.centerIn: parent
      width: Math.min(parent.width - 14, implicitWidth)
      spacing: btn.icon.length > 0 || btn.iconSource.length > 0 ? 7 : 0
      Text {
        visible: btn.icon.length > 0
        text: btn.icon
        color: btn.active ? theme.bgSolid : theme.blue
        font.family: theme.fontFamily
        font.pixelSize: 13
      }
      Image {
        visible: btn.icon.length === 0 && btn.iconSource.length > 0
        source: btn.iconSource
        sourceSize.width: 16
        sourceSize.height: 16
        Layout.preferredWidth: visible ? 16 : 0
        Layout.preferredHeight: visible ? 16 : 0
        fillMode: Image.PreserveAspectFit
        smooth: true
      }
      Text {
        id: labelText
        Layout.fillWidth: true
        text: btn.label
        color: btn.active ? theme.bgSolid : theme.text
        font.family: theme.fontFamily
        font.pixelSize: 12
        font.bold: true
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignHCenter
      }
    }

    MouseArea {
      id: btnMouse
      anchors.fill: parent
      enabled: btn.enabled
      hoverEnabled: true
      cursorShape: btn.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: btn.clicked()
    }
  }

  component RadioSwitch: Item {
    id: radioSwitch
    property bool checked: false
    property bool busy: false
    signal toggled
    implicitWidth: 48
    implicitHeight: 30
    opacity: enabled ? 1 : 0.5
    scale: radioMouse.pressed ? 0.92 : 1

    Behavior on scale {
      MotionNumberAnimation { role: MotionNumberAnimation.Feedback }
    }

    Rectangle {
      id: radioSwitchTrack
      width: 44
      height: 24
      anchors.centerIn: parent
      radius: 12
      color: radioSwitch.checked ? theme.terminalBlue : theme.surfaceMuted
      border.color: radioSwitch.checked ? theme.blue : theme.borderMuted
      border.width: 1

      Behavior on color {
        MotionColorAnimation { role: MotionNumberAnimation.Feedback }
      }
      Behavior on border.color {
        MotionColorAnimation { role: MotionNumberAnimation.Feedback }
      }

      Rectangle {
        id: radioSwitchThumb
        x: radioSwitch.checked ? radioSwitchTrack.width - width - 3 : 3
        anchors.verticalCenter: parent.verticalCenter
        width: 18
        height: 18
        radius: 9
        color: radioSwitch.checked ? theme.bgSolid : theme.mutedAlt
        opacity: radioSwitch.busy ? 0.55 : 1

        Behavior on x {
          MotionNumberAnimation { role: MotionNumberAnimation.FocusTravel }
        }
        Behavior on color {
          MotionColorAnimation { role: MotionNumberAnimation.FocusTravel }
        }

        SequentialAnimation on opacity {
          running: radioSwitch.busy
          loops: Animation.Infinite
          NumberAnimation { to: 0.35; duration: 360 }
          NumberAnimation { to: 0.9; duration: 360 }
        }
      }
    }

    MouseArea {
      id: radioMouse
      anchors.fill: parent
      enabled: radioSwitch.enabled
      hoverEnabled: true
      cursorShape: radioSwitch.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: radioSwitch.toggled()
    }
  }

  component ToggleTile: Rectangle {
    id: tile
    property string icon: ""
    property string title
    property string subtitle
    property bool active: false
    signal clicked
    implicitHeight: 58
    radius: 10
    color: active ? Qt.alpha(theme.blue, 0.16) : tileHover.containsMouse ? theme.surfaceAccent : "transparent"
    border.color: active ? Qt.alpha(theme.blue, 0.48) : tileHover.containsMouse ? theme.borderSubtle : "transparent"
    border.width: 1
    scale: tileHover.pressed ? 0.975 : (tileHover.containsMouse ? 1.012 : 1)

    Behavior on color {
      MotionColorAnimation { role: MotionNumberAnimation.Feedback }
    }
    Behavior on border.color {
      MotionColorAnimation { role: MotionNumberAnimation.Feedback }
    }
    Behavior on scale {
      MotionNumberAnimation { role: MotionNumberAnimation.Feedback }
    }

    RowLayout {
      anchors.fill: parent
      anchors.leftMargin: 10
      anchors.rightMargin: 10
      anchors.topMargin: 8
      anchors.bottomMargin: 8
      spacing: 12
      Text {
        Layout.preferredWidth: 28
        text: tile.icon
        color: tile.active ? theme.blue : theme.foreground
        font.family: theme.fontFamily
        font.pixelSize: 18
        horizontalAlignment: Text.AlignHCenter
      }
      ColumnLayout {
        Layout.fillWidth: true
        spacing: 4
        Text {
          Layout.fillWidth: true
          text: tile.title
          color: theme.foreground
          font.family: theme.fontFamily
          font.pixelSize: 13
          font.bold: true
          elide: Text.ElideRight
        }
        Text {
          Layout.fillWidth: true
          text: tile.subtitle
          color: theme.text
          font.family: theme.fontFamily
          font.pixelSize: 11
          elide: Text.ElideRight
        }
      }

      Text {
        id: tileChevron
        text: "›"
        color: tile.active ? theme.blue : theme.muted
        font.family: theme.fontFamily
        font.pixelSize: 17
        scale: tileHover.containsMouse ? 1.16 : 1

        Behavior on scale {
          MotionNumberAnimation { role: MotionNumberAnimation.Feedback }
        }
      }
    }

    MouseArea {
      id: tileHover
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: tile.clicked()
    }

    Rectangle {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: tile.active ? 3 : 0
      radius: 2
      color: theme.blue
      Behavior on width {
        MotionNumberAnimation { role: MotionNumberAnimation.FocusTravel }
      }
    }
  }

  component IconButton: Rectangle {
    id: iconButton
    property string icon
    property string tooltip: ""
    property bool active: false
    signal clicked
    implicitWidth: 34
    implicitHeight: 34
    radius: 8
    color: active ? theme.terminalBlue : (iconMouse.containsMouse ? theme.surfaceAccent : theme.surfaceMuted)
    border.color: active ? theme.blue : (iconMouse.containsMouse ? theme.borderSubtle : theme.borderMuted)
    border.width: 1
    opacity: enabled ? 1 : 0.46
    scale: iconMouse.pressed ? 0.88 : (iconMouse.containsMouse ? 1.04 : 1)

    Behavior on color {
      MotionColorAnimation { role: MotionNumberAnimation.Feedback }
    }
    Behavior on border.color {
      MotionColorAnimation { role: MotionNumberAnimation.Feedback }
    }
    Behavior on scale {
      MotionNumberAnimation { role: MotionNumberAnimation.Feedback }
    }

    Text {
      anchors.centerIn: parent
      text: iconButton.icon
      color: iconButton.active ? theme.bgSolid : theme.foreground
      font.family: theme.fontFamily
      font.pixelSize: 14
    }

    MouseArea {
      id: iconMouse
      anchors.fill: parent
      enabled: iconButton.enabled
      hoverEnabled: true
      cursorShape: iconButton.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: iconButton.clicked()
    }

    Rectangle {
      visible: iconMouse.containsMouse && iconButton.tooltip.length > 0
      z: 10
      width: tipText.implicitWidth + 14
      height: 26
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.top
      anchors.bottomMargin: 6
      radius: 6
      color: theme.surface
      border.color: theme.borderMuted
      border.width: 1

      Text {
        id: tipText
        anchors.centerIn: parent
        text: iconButton.tooltip
        color: theme.foreground
        font.family: theme.fontFamily
        font.pixelSize: 10
      }
    }
  }

  component GainValueBadge: Rectangle {
    id: gainBadge
    property real value: 0
    property bool muted: false
    readonly property bool boosted: value > 1.005
    implicitWidth: gainText.implicitWidth + (boosted ? 14 : 0)
    implicitHeight: 22
    radius: 7
    color: boosted ? Qt.alpha(theme.orange, 0.14) : "transparent"
    border.color: boosted ? Qt.alpha(theme.orange, 0.48) : "transparent"
    border.width: 1
    opacity: muted ? 0.52 : 1

    Text {
      id: gainText
      anchors.centerIn: parent
      text: (gainBadge.boosted ? "Boost " : "") + Math.round(gainBadge.value * 100) + "%"
      color: gainBadge.boosted ? theme.orange : theme.text
      font.family: theme.fontFamily
      font.pixelSize: gainBadge.boosted ? 9 : 11
      font.bold: gainBadge.boosted
    }
  }

  component GainSlider: Slider {
    id: gainSlider
    property color accent: theme.blue
    property bool boostAllowed: false
    property bool dimmed: false
    readonly property real unityPosition: root.clamp((1 - from) / Math.max(0.001, to - from), 0, 1)
    implicitHeight: 22
    opacity: dimmed ? 0.5 : 1

    background: Rectangle {
      x: gainSlider.leftPadding + gainSlider.handle.width / 2
      y: gainSlider.topPadding + gainSlider.availableHeight / 2 - height / 2
      implicitWidth: 200
      implicitHeight: 5
      width: gainSlider.availableWidth - gainSlider.handle.width
      height: 5
      radius: 3
      color: theme.surfaceMuted
      border.color: Qt.alpha(theme.borderSubtle, 0.7)
      border.width: 1

      Rectangle {
        visible: gainSlider.boostAllowed
        x: parent.width * gainSlider.unityPosition
        width: parent.width * (1 - gainSlider.unityPosition)
        height: parent.height
        radius: parent.radius
        color: Qt.alpha(theme.orange, 0.11)
      }

      Rectangle {
        width: parent.width * Math.min(gainSlider.visualPosition, gainSlider.unityPosition)
        height: parent.height
        radius: parent.radius
        color: gainSlider.accent
      }

      Rectangle {
        visible: gainSlider.boostAllowed && gainSlider.visualPosition > gainSlider.unityPosition
        x: parent.width * gainSlider.unityPosition
        width: parent.width * (gainSlider.visualPosition - gainSlider.unityPosition)
        height: parent.height
        radius: parent.radius
        color: theme.orange
      }

      Rectangle {
        visible: gainSlider.boostAllowed
        x: Math.round(parent.width * gainSlider.unityPosition) - 1
        anchors.verticalCenter: parent.verticalCenter
        width: 2
        height: 11
        radius: 1
        color: theme.foreground
        opacity: 0.44
      }
    }

    handle: Rectangle {
      x: gainSlider.leftPadding + gainSlider.visualPosition * (gainSlider.availableWidth - width)
      y: gainSlider.topPadding + gainSlider.availableHeight / 2 - height / 2
      implicitWidth: 14
      implicitHeight: 14
      radius: 7
      color: gainSlider.boostAllowed && gainSlider.value > 1 ? theme.orange : gainSlider.accent
      border.color: theme.bgSolid
      border.width: 2
    }
  }

  component Bar: Rectangle {
    property real value: 0
    property color accent: theme.blue
    implicitHeight: 8
    radius: 4
    color: theme.surfaceMuted
    Rectangle {
      width: parent.width * root.clamp(parent.value, 0, 1)
      height: parent.height
      radius: parent.radius
      color: parent.accent

      Behavior on width {
        MotionNumberAnimation { role: MotionNumberAnimation.FocusTravel }
      }
      Behavior on color {
        MotionColorAnimation { role: MotionNumberAnimation.Content }
      }
    }
  }

  component OsdRow: RowLayout {
    id: osdRow
    property string icon: ""
    property real level: 0
    property string label: ""
    property color accent: theme.blue
    spacing: 12

    Text {
      text: osdRow.icon
      color: osdRow.accent
      font.family: theme.fontFamily
      font.pixelSize: 17
      font.bold: true
      Layout.preferredWidth: 28
      horizontalAlignment: Text.AlignHCenter
    }
    Bar {
      Layout.fillWidth: true
      value: osdRow.level
      accent: osdRow.accent
    }
    Text {
      text: osdRow.label
      color: theme.text
      font.family: theme.fontFamily
      font.pixelSize: 12
      horizontalAlignment: Text.AlignRight
      Layout.preferredWidth: 38
    }
  }

  component MetricCard: Rectangle {
    id: card
    property string icon: ""
    property string title
    property string subtitle
    property real value: 0
    property real dragValue: value
    property bool dragging: false
    property bool showDivider: true
    readonly property real displayedValue: dragging ? dragValue : value
    property color accent: theme.blue
    signal changed(real value)
    signal toggle
    Layout.fillWidth: true
    implicitHeight: showDivider ? 78 : 68
    radius: 0
    color: "transparent"
    border.color: "transparent"
    border.width: 0

    Rectangle {
      visible: card.showDivider
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      height: 1
      color: theme.borderSubtle
    }

    ColumnLayout {
      anchors.fill: parent
      anchors.leftMargin: 0
      anchors.rightMargin: 0
      anchors.topMargin: card.showDivider ? 13 : 3
      anchors.bottomMargin: 9
      spacing: 6

      RowLayout {
        Layout.fillWidth: true
        Text {
          visible: card.icon.length > 0
          text: card.icon
          color: card.accent
          font.family: theme.fontFamily
          font.pixelSize: 15
          Layout.preferredWidth: 22
        }
        Text {
          Layout.fillWidth: true
          text: card.title
          color: theme.foreground
          font.family: theme.fontFamily
          font.pixelSize: 13
          font.bold: true
          elide: Text.ElideRight
        }
        Text {
          text: Math.round(card.displayedValue * 100) + "%"
          color: theme.text
          font.family: theme.fontFamily
          font.pixelSize: 12
        }
      }
      Text {
        Layout.fillWidth: true
        text: card.subtitle
        color: theme.muted
        font.family: theme.fontFamily
        font.pixelSize: 11
        elide: Text.ElideRight
      }
      GainSlider {
        Layout.fillWidth: true
        from: 0
        to: 1
        value: card.displayedValue
        accent: card.accent
        onPressedChanged: {
          if (pressed) {
            card.dragValue = value;
            card.dragging = true;
          } else if (card.dragging) {
            card.dragging = false;
          }
        }
        onMoved: {
          if (pressed)
            card.dragValue = value;
          card.changed(value);
        }
      }
    }
  }

  component AudioDeviceSection: Rectangle {
    id: audioSection
    property string title
    property string icon
    property var current
    property var devices: []
    property bool expanded: false
    property bool showDivider: true
    property color accent: theme.blue
    signal toggleExpanded
    signal volumeChanged(real value)
    signal toggleMute
    signal choose(var node)
    Layout.fillWidth: true
    implicitHeight: content.implicitHeight + (showDivider ? 20 : 10)
    radius: 0
    color: "transparent"
    border.color: "transparent"
    border.width: 0

    Rectangle {
      visible: audioSection.showDivider
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      height: 1
      color: audioSection.expanded ? Qt.alpha(audioSection.accent, 0.7) : theme.borderSubtle
    }

    ColumnLayout {
      id: content
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.topMargin: audioSection.showDivider ? 12 : 2
      spacing: 9

      RowLayout {
        Layout.fillWidth: true
        spacing: 9

        IconButton {
          icon: audioSection.icon
          active: false
          tooltip: audioSection.current?.audio?.muted ? "Unmute" : "Mute"
          onClicked: audioSection.toggleMute()
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 2
          Text {
            Layout.fillWidth: true
            text: audioSection.title
            color: audioSection.accent
            font.family: theme.fontFamily
            font.pixelSize: 11
            font.bold: true
            elide: Text.ElideRight
          }
          Text {
            Layout.fillWidth: true
            text: root.deviceName(audioSection.current)
            color: theme.foreground
            font.family: theme.fontFamily
            font.pixelSize: 12
            font.bold: true
            elide: Text.ElideRight
          }
        }

        GainValueBadge {
          value: audioSection.current?.audio?.volume || 0
          muted: audioSection.current?.audio?.muted || false
        }

        IconButton {
          icon: audioSection.expanded ? "" : ""
          tooltip: audioSection.expanded ? "Hide devices" : "Show devices"
          onClicked: audioSection.toggleExpanded()
        }
      }

      GainSlider {
        Layout.fillWidth: true
        from: 0
        to: 1.5
        value: audioSection.current?.audio?.volume || 0
        accent: audioSection.accent
        boostAllowed: true
        dimmed: audioSection.current?.audio?.muted || false
        onMoved: {
          if (pressed)
            audioSection.volumeChanged(value);
        }
      }

      ColumnLayout {
        Layout.fillWidth: true
        visible: audioSection.expanded
        spacing: 6
        Repeater {
          model: audioSection.devices
          delegate: DeviceChoiceRow {
            required property var modelData
            icon: audioSection.title === "Input" ? "" : ""
            node: modelData
            active: modelData === audioSection.current
            onClicked: audioSection.choose(modelData)
          }
        }
      }
    }
  }

  component DeviceChoiceRow: Rectangle {
    id: deviceRow
    property string icon
    property var node
    property bool active: false
    signal clicked
    Layout.fillWidth: true
    implicitHeight: 46
    radius: 8
    color: active ? Qt.alpha(theme.blue, 0.28) : theme.surfaceSoft
    border.color: active ? theme.blue : theme.borderMuted
    border.width: 1

    RowLayout {
      anchors.fill: parent
      anchors.margins: 10
      spacing: 10
      Text {
        Layout.preferredWidth: 24
        text: deviceRow.icon
        color: deviceRow.active ? theme.blue : theme.foreground
        font.family: theme.fontFamily
        font.pixelSize: 15
        horizontalAlignment: Text.AlignHCenter
      }
      Text {
        Layout.fillWidth: true
        text: root.deviceName(deviceRow.node)
        color: theme.text
        font.family: theme.fontFamily
        font.pixelSize: 11
        elide: Text.ElideRight
      }
      Text {
        text: deviceRow.active ? "" : ""
        color: theme.green
        font.family: theme.fontFamily
        font.pixelSize: 13
        Layout.preferredWidth: 18
        horizontalAlignment: Text.AlignHCenter
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: deviceRow.clicked()
    }
  }

  component StreamVolumeRow: Rectangle {
    id: row
    property var node
    Layout.fillWidth: true
    readonly property color accent: root.streamAccent(node)
    readonly property real streamVolume: node?.audio?.volume || 0
    readonly property bool streamMuted: node?.audio?.muted || false
    property bool showDivider: true
    implicitHeight: 82
    radius: 0
    color: "transparent"
    border.color: "transparent"
    border.width: 0

    Rectangle {
      visible: row.showDivider
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      height: 1
      color: theme.borderSubtle
      opacity: 0.38
    }

    ColumnLayout {
      anchors.fill: parent
      anchors.leftMargin: 0
      anchors.rightMargin: 0
      anchors.topMargin: 9
      anchors.bottomMargin: 7
      spacing: 6

      RowLayout {
        Layout.fillWidth: true
        spacing: 9

        Rectangle {
          Layout.preferredWidth: 30
          Layout.preferredHeight: 30
          radius: 8
          color: Qt.alpha(row.accent, 0.14)
          border.color: Qt.alpha(row.accent, 0.42)
          border.width: 1

          Text {
            anchors.centerIn: parent
            text: root.streamIcon(node)
            color: row.accent
            font.family: theme.fontFamily
            font.pixelSize: 13
          }
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 1

          Text {
            Layout.fillWidth: true
            text: root.streamName(node)
            color: theme.foreground
            font.family: theme.fontFamily
            font.pixelSize: 11
            font.bold: true
            elide: Text.ElideRight
          }
          Text {
            Layout.fillWidth: true
            text: root.streamSubtitle(node)
            color: theme.muted
            font.family: theme.fontFamily
            font.pixelSize: 9
            elide: Text.ElideRight
          }
        }

        GainValueBadge {
          value: row.streamVolume
          muted: row.streamMuted
        }

        IconButton {
          icon: row.streamMuted ? "󰝟" : ""
          tooltip: row.streamMuted ? "Unmute" : "Mute"
          active: false
          implicitWidth: 30
          implicitHeight: 30
          onClicked: {
            if (node?.audio)
              node.audio.muted = !node.audio.muted;
          }
        }
      }

      GainSlider {
        Layout.fillWidth: true
        from: 0
        to: 1
        value: Math.min(row.streamVolume, 1)
        accent: row.accent
        boostAllowed: false
        dimmed: row.streamMuted
        onMoved: {
          if (pressed && node?.audio) {
            node.audio.volume = value;
            node.audio.muted = false;
          }
        }
      }
    }
  }

  component MiniGauge: Rectangle {
    id: gauge
    property string label
    property string textValue
    property real value: 0
    property color accent: theme.blue
    implicitHeight: 78
    radius: 8
    color: theme.surfaceRaised
    border.color: theme.borderMuted
    border.width: 1
    ColumnLayout {
      anchors.fill: parent
      anchors.margins: 10
      spacing: 7
      RowLayout {
        Layout.fillWidth: true
        Text {
          Layout.fillWidth: true
          text: gauge.label
          color: theme.foreground
          font.family: theme.fontFamily
          font.pixelSize: 12
          font.bold: true
        }
        Text {
          text: gauge.textValue
          color: theme.text
          font.family: theme.fontFamily
          font.pixelSize: 11
        }
      }
      Bar {
        Layout.fillWidth: true
        value: gauge.value
        accent: gauge.accent
      }
    }
  }

  component NotificationVisual: Rectangle {
    id: notificationVisual
    property var notification
    property real visualSize: 28
    property string fallbackIcon: root.notificationIsCritical(notification) ? "" : ""
    property color accent: root.notificationIsCritical(notification) ? theme.red : theme.blue

    implicitWidth: visualSize
    implicitHeight: visualSize
    radius: Math.min(10, visualSize / 3)
    color: Qt.alpha(accent, 0.14)
    clip: true

    Image {
      id: notificationImage
      anchors.fill: parent
      anchors.margins: 3
      source: root.notificationVisualSource(notificationVisual.notification)
      sourceSize.width: Math.max(1, notificationVisual.visualSize - 6)
      sourceSize.height: Math.max(1, notificationVisual.visualSize - 6)
      fillMode: Image.PreserveAspectFit
      smooth: true
      asynchronous: true
      visible: status === Image.Ready
    }

    Text {
      anchors.centerIn: parent
      visible: !notificationImage.visible
      text: notificationVisual.fallbackIcon
      color: notificationVisual.accent
      font.family: theme.fontFamily
      font.pixelSize: Math.max(12, notificationVisual.visualSize * 0.46)
    }
  }

  component NotificationProgress: ColumnLayout {
    id: notificationProgress
    property var progressData: ({ visible: false, value: 0, text: "" })

    Layout.fillWidth: true
    visible: Boolean(progressData?.visible)
    spacing: 4

    RowLayout {
      Layout.fillWidth: true
      Text {
        Layout.fillWidth: true
        text: "Progress"
        color: theme.mutedAlt
        font.family: theme.fontFamily
        font.pixelSize: 9
      }
      Text {
        text: notificationProgress.progressData?.text || ""
        color: theme.terminalBlue
        font.family: theme.fontFamily
        font.pixelSize: 9
        font.bold: true
      }
    }

    Bar {
      Layout.fillWidth: true
      value: Number(notificationProgress.progressData?.value || 0)
      accent: theme.blue
    }
  }

  component NotificationInlineReply: RowLayout {
    id: inlineReply
    property var notification
    readonly property bool available: Boolean(notification?.hasInlineReply) && Boolean(notification?.sendInlineReply)

    function submit() {
      const message = replyField.text.trim();
      if (!available || message.length === 0)
        return;

      notification.sendInlineReply(message);
      replyField.text = "";
      if (!root.notificationIsResident(notification))
        notification.dismiss();
    }

    Layout.fillWidth: true
    visible: available
    spacing: 7

    TextField {
      id: replyField
      Layout.fillWidth: true
      implicitHeight: 34
      placeholderText: String(inlineReply.notification?.inlineReplyPlaceholder || "Reply")
      color: theme.text
      placeholderTextColor: theme.mutedAlt
      font.family: theme.fontFamily
      font.pixelSize: 11
      selectByMouse: true
      onAccepted: inlineReply.submit()

      background: Rectangle {
        radius: 8
        color: theme.surfaceMuted
        border.color: replyField.activeFocus ? theme.blue : theme.borderMuted
        border.width: 1
      }
    }

    PillButton {
      label: "Send"
      maximumWidth: 82
      enabled: replyField.text.trim().length > 0
      onClicked: inlineReply.submit()
    }
  }

  component NotificationGroup: Rectangle {
    id: notificationGroup
    property var group
    readonly property bool expanded: root.notificationGroupExpanded(group?.key || "")
    readonly property var visibleItems: expanded ? (group?.items || []) : (group?.items || []).slice(0, 1)
    readonly property bool canExpand: (group?.items || []).length > 1
    readonly property var firstNotification: root.itemNotification((group?.items || [])[0])

    Layout.fillWidth: true
    implicitHeight: groupContent.implicitHeight + 20
    radius: 11
    color: Qt.alpha(theme.surfaceGlass, 0.58)
    border.color: group?.critical ? Qt.alpha(theme.red, 0.5)
      : group?.resident ? Qt.alpha(theme.purple, 0.46)
      : Qt.alpha(theme.borderSubtle, 0.58)
    border.width: 1

    Behavior on implicitHeight {
      MotionNumberAnimation { role: MotionNumberAnimation.Content }
    }
    Behavior on border.color {
      MotionColorAnimation { role: MotionNumberAnimation.Content }
    }

    ColumnLayout {
      id: groupContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: 10
      spacing: 8

      Item {
        Layout.fillWidth: true
        implicitHeight: 30

        RowLayout {
          anchors.fill: parent
          spacing: 8

          NotificationVisual {
            notification: notificationGroup.firstNotification
            Layout.preferredWidth: 28
            Layout.preferredHeight: 28
            fallbackIcon: notificationGroup.group?.critical ? "\uf071" : notificationGroup.group?.resident ? "\uf08d" : "\uf0f3"
            accent: notificationGroup.group?.critical ? theme.red : notificationGroup.group?.resident ? theme.purple : theme.blue
          }

          Text {
            Layout.fillWidth: true
            text: notificationGroup.group?.appName || "Application"
            color: theme.foreground
            font.family: theme.fontFamily
            font.pixelSize: 12
            font.bold: true
            elide: Text.ElideRight
          }

          Rectangle {
            visible: notificationGroup.canExpand
            implicitWidth: groupCount.implicitWidth + 12
            implicitHeight: 22
            radius: 11
            color: theme.surfaceMuted

            Text {
              id: groupCount
              anchors.centerIn: parent
              text: String(notificationGroup.group?.items?.length || 0)
              color: theme.terminalBlue
              font.family: theme.fontFamily
              font.pixelSize: 10
              font.bold: true
            }
          }

          Text {
            text: root.relativeNotificationTime(notificationGroup.group?.latestTime || 0)
            color: theme.mutedAlt
            font.family: theme.fontFamily
            font.pixelSize: 10
          }

          Text {
            visible: notificationGroup.canExpand
            text: notificationGroup.expanded ? "" : ""
            color: theme.mutedAlt
            font.family: theme.fontFamily
            font.pixelSize: 12
            Layout.preferredWidth: 18
            horizontalAlignment: Text.AlignHCenter
          }
        }

        MouseArea {
          anchors.fill: parent
          enabled: notificationGroup.canExpand
          cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: root.toggleNotificationGroup(notificationGroup.group.key)
        }
      }

      Repeater {
        model: notificationGroup.visibleItems
        delegate: NotificationItem {
          required property var modelData
          item: modelData
          onDismiss: root.dismissNotification(item.id)
        }
      }
    }
  }

  component NotificationItem: Rectangle {
    id: notifRow
    property var item
    readonly property var notification: root.itemNotification(item)
    readonly property var actions: root.visibleNotificationActions(notification)
    readonly property string bodyText: root.sanitizeNotificationBody(notification?.body || "")
    readonly property bool hasBody: bodyText.length > 0 && bodyText !== "."
    readonly property var progressData: root.notificationProgress(notification)
    readonly property bool hasDefaultAction: root.defaultNotificationAction(notification) !== null
    signal dismiss
    Layout.fillWidth: true
    implicitHeight: Math.max(74, notifColumn.implicitHeight + 20)
    radius: 9
    color: theme.surfaceAccent
    border.color: Qt.alpha(theme.borderSubtle, 0.58)
    border.width: 1

    MouseArea {
      anchors.fill: parent
      enabled: notifRow.hasDefaultAction
      hoverEnabled: enabled
      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: root.invokeDefaultNotificationAction(notifRow.notification)
    }

    ColumnLayout {
      id: notifColumn
      anchors.fill: parent
      anchors.margins: 10
      spacing: 7
      RowLayout {
        Layout.fillWidth: true
        spacing: 8
        NotificationVisual {
          notification: notifRow.notification
          visualSize: 24
          Layout.preferredWidth: 24
          Layout.preferredHeight: 24
        }
        Text {
          Layout.fillWidth: true
          text: notifRow.notification?.summary || "Notification"
          color: theme.foreground
          font.family: theme.fontFamily
          font.pixelSize: 12
          font.bold: true
          elide: Text.ElideRight
        }
        Text {
          text: root.relativeNotificationTime(notifRow.item?.time || 0)
          color: theme.mutedAlt
          font.family: theme.fontFamily
          font.pixelSize: 9
        }
        IconButton {
          icon: ""
          tooltip: "Dismiss"
          onClicked: notifRow.dismiss()
        }
      }
      Text {
        Layout.fillWidth: true
        visible: notifRow.hasBody
        text: notifRow.bodyText
        textFormat: Text.StyledText
        linkColor: theme.terminalBlue
        color: theme.text
        font.family: theme.fontFamily
        font.pixelSize: 11
        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
        maximumLineCount: 4
        elide: Text.ElideRight
        onLinkActivated: function(link) { root.openNotificationLink(link); }
      }
      NotificationProgress {
        progressData: notifRow.progressData
      }
      NotificationInlineReply {
        notification: notifRow.notification
      }
      RowLayout {
        Layout.fillWidth: true
        visible: notifRow.actions.length > 0
        spacing: 6
        Repeater {
          model: root.actionEntries(notifRow.actions, notifRow.notification)
          delegate: PillButton {
            required property var modelData
            label: root.actionLabel(modelData.action)
            iconSource: root.notificationActionIconSource(modelData.notification, modelData.action)
            onClicked: root.invokeNotificationAction(modelData.action)
          }
        }
      }
    }
  }

  component NotificationToast: Rectangle {
    id: toast
    property var item
    readonly property var notification: root.itemNotification(item)
    readonly property var actions: root.visibleNotificationActions(notification)
    readonly property string bodyText: root.sanitizeNotificationBody(notification?.body || "")
    readonly property bool hasBody: bodyText.length > 0 && bodyText !== "."
    readonly property var progressData: root.notificationProgress(notification)
    readonly property bool persistent: root.notificationPopupPersistent(notification)
    readonly property bool hasDefaultAction: root.defaultNotificationAction(notification) !== null
    readonly property int actionBottomGap: actions.length > 0 ? 8 : 0
    property bool closing: false
    property bool dismissOnClose: false
    signal dismiss
    signal hide
    Layout.fillWidth: true
    implicitHeight: Math.max(86, toastColumn.implicitHeight + 22 + actionBottomGap)
    radius: 12
    color: theme.surfaceGlassStrong
    border.color: theme.borderSubtle
    border.width: 1
    opacity: 0
    x: 24
    scale: 0.96
    transformOrigin: Item.TopRight

    function close(removeNotification) {
      if (closing)
        return;
      closing = true;
      dismissOnClose = removeNotification;
      lifetime.stop();
      hideAnim.start();
    }

    Behavior on y {
      MotionNumberAnimation { role: MotionNumberAnimation.FocusTravel }
    }

    Component.onCompleted: {
      lifetime.start(Number(item?.popupTime || Date.now()), Number(item?.pausedMs || 0));
      showAnim.start();
    }

    Connections {
      target: toast.notification
      function onExpireTimeoutChanged() { lifetime.restart(true); }
      function onAppNameChanged() { lifetime.restart(true); }
      function onAppIconChanged() { lifetime.restart(true); }
      function onSummaryChanged() { lifetime.restart(true); }
      function onBodyChanged() { lifetime.restart(true); }
      function onActionsChanged() { lifetime.restart(true); }
      function onImageChanged() { lifetime.restart(true); }
      function onHasInlineReplyChanged() { lifetime.restart(true); }
      function onHintsChanged() { lifetime.restart(true); }
    }

    ParallelAnimation {
      id: showAnim
      MotionNumberAnimation { target: toast; property: "opacity"; from: 0; to: 1; role: MotionNumberAnimation.Content }
      MotionNumberAnimation { target: toast; property: "x"; from: 32; to: 0; role: MotionNumberAnimation.Content }
      MotionNumberAnimation { target: toast; property: "scale"; from: 0.96; to: 1; role: MotionNumberAnimation.Content }
    }

    ParallelAnimation {
      id: hideAnim
      MotionNumberAnimation { target: toast; property: "opacity"; to: 0; role: MotionNumberAnimation.SurfaceExit }
      MotionNumberAnimation { target: toast; property: "x"; to: 40; role: MotionNumberAnimation.SurfaceExit }
      MotionNumberAnimation { target: toast; property: "scale"; to: 0.97; role: MotionNumberAnimation.SurfaceExit }
      onFinished: {
        if (toast.dismissOnClose)
          toast.dismiss();
        else
          toast.hide();
      }
    }

    MouseArea {
      anchors.fill: parent
      enabled: toast.hasDefaultAction
      hoverEnabled: enabled
      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: root.invokeDefaultNotificationAction(toast.notification)
    }

    ColumnLayout {
      id: toastColumn
      anchors.fill: parent
      anchors.margins: 13
      anchors.bottomMargin: 16 + toast.actionBottomGap
      spacing: 8

      RowLayout {
        Layout.fillWidth: true
        spacing: 9
        NotificationVisual {
          notification: toast.notification
          visualSize: 34
          Layout.preferredWidth: 34
          Layout.preferredHeight: 34
        }
        ColumnLayout {
          Layout.fillWidth: true
          spacing: 2
          Text {
            Layout.fillWidth: true
            text: root.notificationAppName(toast.notification)
            color: theme.terminalBlue
            font.family: theme.fontFamily
            font.pixelSize: 11
            font.bold: true
            elide: Text.ElideRight
          }
          Text {
            Layout.fillWidth: true
            text: toast.notification?.summary || ""
            color: theme.foreground
            font.family: theme.fontFamily
            font.pixelSize: 14
            font.bold: true
            elide: Text.ElideRight
          }
        }
        IconButton {
          icon: ""
          tooltip: "Dismiss"
          onClicked: toast.close(true)
        }
      }

      Text {
        Layout.fillWidth: true
        visible: toast.hasBody
        text: toast.bodyText
        textFormat: Text.StyledText
        linkColor: theme.terminalBlue
        color: theme.text
        font.family: theme.fontFamily
        font.pixelSize: 13
        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
        maximumLineCount: 3
        elide: Text.ElideRight
        onLinkActivated: function(link) { root.openNotificationLink(link); }
      }

      NotificationProgress {
        progressData: toast.progressData
      }

      NotificationInlineReply {
        notification: toast.notification
      }

      Flow {
        id: actionFlow
        Layout.fillWidth: true
        Layout.preferredHeight: childrenRect.height
        visible: toast.actions.length > 0
        spacing: root.notificationActionSpacing
        Repeater {
          model: root.actionEntries(toast.actions, toast.notification)
          delegate: PillButton {
            required property var modelData
            label: root.actionLabel(modelData.action)
            iconSource: root.notificationActionIconSource(modelData.notification, modelData.action)
            maximumWidth: actionFlow.width
            onClicked: root.invokeNotificationAction(modelData.action)
          }
        }
      }
    }

    ToastLifetimeBar {
      id: lifetime
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.leftMargin: 12
      anchors.rightMargin: 12
      anchors.bottomMargin: 7
      duration: root.notificationPopupDuration(toast.notification)
      persistent: toast.persistent
      trackColor: Qt.alpha(theme.surfaceMuted, 0.72)
      accentColor: theme.blue
      hoverAccentColor: theme.purple
      onExpired: {
        if (toast.item?.id !== undefined)
          toast.close(false);
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
      onEntered: lifetime.pause()
      onExited: {
        const popupId = toast.item?.id;
        lifetime.resume();
        if (popupId !== undefined)
          root.patchPopup(popupId, {
            pausedMs: lifetime.pausedMs
          });
      }
    }
  }

  component BluetoothDeviceRow: Rectangle {
    id: bluetoothRow
    property var device
    property bool operationTarget: root.bluetoothOperationAddress === device.address
    Layout.fillWidth: true
    implicitHeight: 64
    radius: 10
    color: device.connected
      ? Qt.alpha(theme.purple, 0.14)
      : (operationTarget ? Qt.alpha(theme.purple, 0.08) : (bluetoothHover.containsMouse ? theme.surfaceAccent : "transparent"))
    border.color: device.connected
      ? Qt.alpha(theme.purple, 0.45)
      : (operationTarget ? Qt.alpha(theme.purple, 0.25) : Qt.alpha(theme.borderSubtle, 0.28))
    border.width: 1

    RowLayout {
      anchors.fill: parent
      anchors.leftMargin: 10
      anchors.rightMargin: 9
      spacing: 10

      Rectangle {
        Layout.preferredWidth: 38
        Layout.preferredHeight: 38
        radius: 12
        color: Qt.alpha(bluetoothRow.device.connected ? theme.purple : theme.surfaceMuted, bluetoothRow.device.connected ? 0.18 : 0.82)

        Text {
          anchors.centerIn: parent
          text: root.bluetoothDeviceIcon(bluetoothRow.device)
          color: bluetoothRow.device.connected ? theme.purple : theme.foreground
          font.family: theme.fontFamily
          font.pixelSize: 17
        }
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 2

        Text {
          Layout.fillWidth: true
          text: bluetoothRow.device.name
          color: theme.foreground
          font.family: theme.fontFamily
          font.pixelSize: 13
          font.bold: true
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          text: root.bluetoothDeviceDescription(bluetoothRow.device)
          color: bluetoothRow.device.connected ? theme.purple : theme.text
          font.family: theme.fontFamily
          font.pixelSize: 11
          elide: Text.ElideRight
        }
      }

      IconButton {
        visible: bluetoothRow.device.paired
        icon: root.pendingBluetoothForgetAddress === bluetoothRow.device.address ? "" : "󰆴"
        tooltip: root.pendingBluetoothForgetAddress === bluetoothRow.device.address
          ? "Confirm forgetting " + bluetoothRow.device.name
          : "Forget " + bluetoothRow.device.name
        enabled: !root.bluetoothBusy
        onClicked: root.requestForgetBluetoothDevice(bluetoothRow.device)
      }

      PillButton {
        label: root.bluetoothDeviceAction(bluetoothRow.device)
        maximumWidth: 126
        active: !bluetoothRow.device.paired
        enabled: !root.bluetoothBusy
        onClicked: root.runBluetoothDeviceAction(bluetoothRow.device)
      }
    }

    MouseArea {
      id: bluetoothHover
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
    }
  }

  component WifiNetworkRow: Rectangle {
    id: wifiRow
    property var network
    property bool expanded: root.pendingSsid === network.name
    property bool revealPassword: false
    property bool operationTarget: network.stateChanging
    Layout.fillWidth: true
    implicitHeight: expanded ? 120 : 62
    radius: 10
    color: network.connected
      ? Qt.alpha(theme.blue, 0.13)
      : (operationTarget ? Qt.alpha(theme.blue, 0.07) : (wifiHover.containsMouse ? theme.surfaceAccent : "transparent"))
    border.color: network.connected
      ? Qt.alpha(theme.blue, 0.42)
      : (operationTarget ? Qt.alpha(theme.blue, 0.24) : Qt.alpha(theme.borderSubtle, 0.28))
    border.width: 1

    onExpandedChanged: {
      if (expanded)
        passwordInput.forceActiveFocus();
    }

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: 10
      spacing: 8

      RowLayout {
        Layout.fillWidth: true
        spacing: 10
        SignalMeter {
          Layout.preferredWidth: 34
          Layout.preferredHeight: 18
          value: root.wifiSignal(wifiRow.network)
          accent: wifiRow.network.connected ? theme.blue : theme.mutedAlt
        }
        ColumnLayout {
          Layout.fillWidth: true
          spacing: 2
          Text {
            Layout.fillWidth: true
            text: wifiRow.network.name
            color: theme.foreground
            font.family: theme.fontFamily
            font.pixelSize: 13
            font.bold: true
            elide: Text.ElideRight
          }
          Text {
            Layout.fillWidth: true
            text: root.wifiNetworkDescription(wifiRow.network)
            color: wifiRow.network.connected ? theme.blue : theme.text
            font.family: theme.fontFamily
            font.pixelSize: 11
            elide: Text.ElideRight
          }
        }
        PillButton {
          label: wifiRow.expanded
            && !wifiRow.network.connected
            && !wifiRow.network.stateChanging
            ? "Connect"
            : root.wifiNetworkAction(wifiRow.network)
          maximumWidth: 126
          active: false
          enabled: !root.wifiBusy
            && (!wifiRow.expanded || root.pendingPassword.length > 0)
          onClicked: {
            if (wifiRow.network.connected) {
              root.disconnectWifi(wifiRow.network);
            } else if (wifiRow.expanded) {
              root.connectWifi(wifiRow.network, root.pendingPassword);
            } else if (wifiRow.network.known) {
              root.connectWifi(wifiRow.network, "");
            } else if (root.wifiNetworkNeedsPsk(wifiRow.network)) {
              root.requestWifiPassword(wifiRow.network);
            } else {
              root.connectWifi(wifiRow.network, "");
            }
          }
        }
      }

      RowLayout {
        Layout.fillWidth: true
        visible: wifiRow.expanded
        spacing: 8
        TextField {
          id: passwordInput
          Layout.fillWidth: true
          placeholderText: "Network password"
          placeholderTextColor: theme.mutedAlt
          echoMode: wifiRow.revealPassword ? TextInput.Normal : TextInput.Password
          text: root.pendingPassword
          onTextEdited: root.pendingPassword = text
          enabled: !root.wifiBusy
          color: theme.text
          font.family: theme.fontFamily
          font.pixelSize: 12
          background: Rectangle {
            radius: 8
            color: theme.bgSolid
            border.color: theme.borderMuted
            border.width: 1
          }
          onAccepted: {
            if (root.pendingPassword.length > 0)
              root.connectWifi(wifiRow.network, root.pendingPassword);
          }
          Keys.onEscapePressed: {
            root.pendingSsid = "";
            root.pendingPassword = "";
            root.connectionTargetSsid = "";
          }
        }
        IconButton {
          icon: wifiRow.revealPassword ? "󰈈" : "󰈉"
          tooltip: wifiRow.revealPassword ? "Hide password" : "Show password"
          enabled: !root.wifiBusy
          onClicked: wifiRow.revealPassword = !wifiRow.revealPassword
        }
        PillButton {
          label: "Cancel"
          enabled: !root.wifiBusy
          onClicked: {
            root.pendingSsid = "";
            root.pendingPassword = "";
            root.connectionTargetSsid = "";
          }
        }
      }
    }

    Connections {
      target: wifiRow.network

      function onConnectionFailed(reason) {
        root.handleWifiConnectionFailure(wifiRow.network, reason);
      }

      function onConnectedChanged() {
        if (wifiRow.network.connected
            && root.connectionTargetSsid === wifiRow.network.name) {
          root.pendingSsid = "";
          root.pendingPassword = "";
          root.connectionTargetSsid = "";
          root.wifiError = "";
        }
      }
    }

    MouseArea {
      id: wifiHover
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
    }
  }

  component SignalMeter: Item {
    id: meter
    property int value: 0
    property color accent: theme.green

    Row {
      anchors.centerIn: parent
      spacing: 2

      Rectangle {
        width: 5
        height: 4
        radius: 1
        anchors.bottom: parent.bottom
        color: meter.value >= 1 ? meter.accent : Qt.alpha(meter.accent, 0.22)
      }

      Rectangle {
        width: 5
        height: 7
        radius: 1
        anchors.bottom: parent.bottom
        color: meter.value >= 35 ? meter.accent : Qt.alpha(meter.accent, 0.22)
      }

      Rectangle {
        width: 5
        height: 11
        radius: 1
        anchors.bottom: parent.bottom
        color: meter.value >= 60 ? meter.accent : Qt.alpha(meter.accent, 0.22)
      }

      Rectangle {
        width: 5
        height: 15
        radius: 1
        anchors.bottom: parent.bottom
        color: meter.value >= 80 ? meter.accent : Qt.alpha(meter.accent, 0.22)
      }
    }
  }
}
