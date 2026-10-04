pragma ComponentBehavior: Bound

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
import "NotificationHistory.js" as History

Scope {
  id: root

  required property var barSurface

  signal notificationPopupsCloseRequested

  Theme {
    id: theme
  }

  ShellConfig {
    id: shellConfig
  }
  MotionTransition {
    id: mainSurfaceTransition
    requested: root.open
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
  readonly property bool wifiToggleAvailable: wifi.backendAvailable && wifi.hardwareEnabled && wifi.device !== null && !wifiBusy
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
  property string brightnessValuePath: ""
  property bool brightnessSupported: false
  property bool brightnessWritable: false
  property int pendingBrightnessPercent: 0
  property bool brightnessReady: false
  property bool displaysReady: false
  property var displays: []
  property bool displayProfileAvailable: false
  property string displayPrimary: ""
  property string displayInitialPrimary: ""
  property string displaySelected: ""
  property var displayDraft: ({})
  property string displayOperation: ""
  property string displayError: ""
  property string displayPendingToken: ""
  property int displayConfirmSeconds: 0
  property bool displayRefreshPending: false
  readonly property bool displayEditorLocked: displayPendingToken.length > 0 || displayOperation.length > 0
  property bool volumeReady: false
  readonly property int osdTimeout: 1100
  readonly property int osdRowHeight: 38
  readonly property int osdRowSpacing: 10
  readonly property int osdVerticalPadding: 24
  readonly property int osdRowCount: osdModel.count
  readonly property bool osdVisible: osdRowCount > 0
  readonly property int osdBoxHeight: osdVerticalPadding + osdRowCount * osdRowHeight + Math.max(0, osdRowCount - 1) * osdRowSpacing
  readonly property var osdKinds: ({
      brightness: {
        icon: "󰃠",
        accent: theme.utility
      },
      volume: {
        icon: "",
        accent: theme.info
      },
      fallback: {
        icon: "󰘳",
        accent: theme.special
      }
    })
  property var notifications: []
  property var clearedNotifications: []
  property var expandedNotificationGroups: ({})
  property double notificationTimelineNow: Date.now()
  property var notificationPopupById: ({})
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
  readonly property bool audioDetailsActive: open && page === "audio"
  readonly property var audioNodes: audioDetailsActive ? Pipewire.nodes.values : []
  readonly property var outputDevices: audioNodes.filter(function (node) {
    return Boolean(node?.audio && node.ready && !node.isStream && node.isSink);
  })
  readonly property var inputDevices: audioNodes.filter(function (node) {
    return Boolean(node?.audio && node.ready && !node.isStream && !node.isSink);
  })
  readonly property var appStreams: audioNodes.filter(function (node) {
    return Boolean(node?.audio && node.isStream);
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
        target: pageTranslation
        property: "x"
        to: -root.pageDirection * 18
        role: MotionNumberAnimation.SurfaceExit
      }
    }
    ScriptAction {
      script: {
        root.displayedPage = root.page;
        pageTranslation.x = root.pageDirection * 18;
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
        target: pageTranslation
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
    return Boolean(notification?.resident) || hintBoolean(notification, "resident", false);
  }

  function notificationPopupPersistent(notification) {
    return notificationIsResident(notification) || Number(notification?.expireTimeout || -1) === 0 || Boolean(notification?.hasInlineReply);
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
    return left.localeCompare(right, undefined, {
      sensitivity: "accent"
    }) === 0;
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
    if (role && !details.some(function (detail) {
      return sameStreamLabel(detail, role);
    }))
      details.push(role);
    return details.join(" · ");
  }

  function streamIcon(node) {
    return streamProperty(node, "media.class") === "Stream/Input/Audio" ? "" : "󰎆";
  }

  function streamAccent(node) {
    return streamProperty(node, "media.class") === "Stream/Input/Audio" ? theme.special : theme.info;
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

  function notificationActions(actions) {
    return (actions || []).filter(function (action) {
      const label = String(action?.text || "").trim();
      return action && label.length > 0 && action.invoke;
    });
  }

  function visibleNotificationActions(notification) {
    return notificationActions(notification?.actions).filter(function (action) {
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
    return (actions || []).map(function (action) {
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
      return wifi.changingNetwork?.name ? "Connecting to " + wifi.changingNetwork.name + "…" : "Connecting…";
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
    return network?.security === WifiSecurityType.WpaPsk || network?.security === WifiSecurityType.Wpa2Psk || network?.security === WifiSecurityType.Sae;
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

    if (reason === ConnectionFailReason.WifiAuthTimeout || reason === ConnectionFailReason.WifiClientFailed) {
      wifiError = "Authentication failed for " + String(network?.name || "this network");
    } else if (reason === ConnectionFailReason.WifiNetworkLost) {
      wifiError = "The network disappeared while connecting";
    } else {
      wifiError = "Could not connect to " + String(network?.name || "this network");
    }
  }

  function bluetoothConnectedDevices() {
    return bluetoothDevices.filter(function (device) {
      return Boolean(device?.connected);
    });
  }

  function bluetoothPairedDevices() {
    return bluetoothDevices.filter(function (device) {
      return Boolean(device?.paired);
    });
  }

  function bluetoothNearbyDevices() {
    return bluetoothDevices.filter(function (device) {
      return !Boolean(device?.paired);
    });
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
    const cleaned = String(message || "").replace(/\x1b\[[0-9;]*m/g, "").replace(/^\s*Failed to [^:]+:\s*/i, "").replace(/^\s*Error:\s*/i, "").replace(/org\.bluez\.Error\.[A-Za-z]+\s*/g, "").replace(/\s+/g, " ").trim();
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
    return String(value || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\"/g, "&quot;").replace(/'/g, "&#39;");
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
    return String(body || "").replace(/<[^>]*>/g, function (tag) {
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
    }).replace(/\r\n?|\n/g, "<br>");
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
      return {
        visible: false,
        value: 0,
        text: ""
      };

    const value = Number(rawValue);
    let maximum = Number(hintValue(notification, "value-max"));
    if (!isFinite(maximum) || maximum <= 0)
      maximum = 100;
    if (!isFinite(value) || value < 0)
      return {
        visible: false,
        value: 0,
        text: ""
      };

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
    const silentBluetoothConnection = String(notification?.appName || "").trim().toLowerCase() === "blueman" && Boolean(notification?.transient);
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
    const index = notifications.findIndex(function (n) {
      return n.id === id;
    });
    if (index < 0) {
      const clearedIndex = clearedNotifications.findIndex(function (n) {
        return n.id === id;
      });
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
    notifications = restored.concat(notifications).sort(function (a, b) {
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
    const popup = Object.assign({
      popupTime: Date.now(),
      pausedMs: 0
    }, item);
    const existing = popupIndex(popup.id);
    if (existing >= 0)
      notificationPopupModel.remove(existing);

    setPopupData(popup);
    notificationPopupModel.insert(0, {
      popupId: popup.id
    });

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

  function toggleDnd() {
    dnd = !dnd;
    dndFile.setText(dnd ? "1" : "0");
  }

  // A page transition commits displayedPage after the exit animation. Choose
  // keyboard focus from that committed header, rather than the previous page.
  function focusKeyboardHeader() {
    Qt.callLater(function () {
      if (root.open && mainWindow.keyboardRequested && !mainInputIntent.pointerActive && root.displayedPage === root.page)
        mainHeader.focusDefault();
    });
  }

  onDisplayedPageChanged: focusKeyboardHeader()

  function openPanel(keyboard = true) {
    mainWindow.keyboardRequested = keyboard;
    open = true;
    if (keyboard) {
      mainInputIntent.claimKeyboard();
      focusKeyboardHeader();
    } else {
      mainInputIntent.claimPointer();
    }
  }

  function toggleOpen(keyboard = true) {
    if (open)
      open = false;
    else
      openPanel(keyboard);
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
      Qt.callLater(function () {
        root.requestBluetoothRefresh(process);
      });
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

  readonly property bool displayHasChanges: displayPrimary !== displayInitialPrimary || displays.some(function (output) {
    const draft = displayDraft[output.name] || {};
    return String(draft.mode) !== String(output.mode) || Number(draft.scale) !== Number(output.scale) || String(draft.position) !== String(output.position || "0x0");
  })

  function displayOutput(name) {
    return displays.find(function (output) {
      return String(output?.name || "") === String(name || "");
    }) || null;
  }

  function selectedDisplayOutput() {
    return displayOutput(displaySelected);
  }

  function displayName(output) {
    const description = String(output?.description || "").trim();
    return description.length > 0 ? description : String(output?.name || "Display");
  }

  function displayModeLabel(mode) {
    return String(mode || "preferred").replace("@", " @ ") + (String(mode || "").includes("@") ? " Hz" : "");
  }

  function displaySummaryText() {
    if (!displaysReady)
      return "Detecting displays";
    if (displays.length === 0)
      return "No displays";
    const active = displays.filter(function (output) {
      return Boolean(output.enabled);
    });
    if (active.length === 1)
      return displayName(active[0]);
    const mirrored = active.some(function (output) {
      return String(output.mirror || "").length > 0;
    });
    return active.length + " displays · " + (mirrored ? "Duplicate" : "Extend");
  }

  function displayDraftValue(name, field, fallback) {
    const outputDraft = displayDraft[String(name || "")] || {};
    return outputDraft[field] === undefined ? fallback : outputDraft[field];
  }

  function setDisplayDraftValue(name, field, value) {
    const next = Object.assign({}, displayDraft);
    const outputDraft = Object.assign({}, next[String(name)] || {});
    outputDraft[field] = value;
    next[String(name)] = outputDraft;
    displayDraft = next;
  }

  function parseDisplayPosition(position) {
    const match = /^(-?\d+)x(-?\d+)$/.exec(String(position || ""));
    return match ? {
      x: Number(match[1]),
      y: Number(match[2])
    } : {
      x: 0,
      y: 0
    };
  }

  function displayDraftPosition(output) {
    return parseDisplayPosition(displayDraftValue(output?.name, "position", output?.position || "0x0"));
  }

  function moveDisplayDraft(name, x, y) {
    const next = Object.assign({}, displayDraft);
    const moved = Object.assign({}, next[String(name)] || {});
    moved.position = Math.round(x) + "x" + Math.round(y);
    next[String(name)] = moved;

    let minX = Number.POSITIVE_INFINITY;
    let minY = Number.POSITIVE_INFINITY;
    for (let i = 0; i < displays.length; i++) {
      const output = displays[i];
      if (!output.enabled)
        continue;
      const draft = next[String(output.name)] || {};
      const position = parseDisplayPosition(draft.position === undefined ? output.position : draft.position);
      minX = Math.min(minX, position.x);
      minY = Math.min(minY, position.y);
    }
    if (!Number.isFinite(minX) || !Number.isFinite(minY))
      return;

    for (let i = 0; i < displays.length; i++) {
      const output = displays[i];
      if (!output.enabled)
        continue;
      const key = String(output.name);
      const draft = Object.assign({}, next[key] || {});
      const position = parseDisplayPosition(draft.position === undefined ? output.position : draft.position);
      draft.position = Math.round(position.x - minX) + "x" + Math.round(position.y - minY);
      next[key] = draft;
    }
    displayDraft = next;
  }

  function rebuildDisplayDraft() {
    const next = {};
    for (let i = 0; i < displays.length; i++) {
      const output = displays[i];
      next[String(output.name)] = {
        mode: String(output.mode),
        scale: Number(output.scale),
        position: String(output.position || "0x0")
      };
    }
    displayDraft = next;
  }

  function displayCurrentPreset() {
    const active = displays.filter(function (output) {
      return Boolean(output.enabled);
    });
    if (active.length === 0)
      return "";
    if (active.some(function (output) {
      return String(output.mirror || "").length > 0;
    }))
      return "duplicate";
    if (active.every(function (output) {
      return Boolean(output.internal);
    }))
      return "internal";
    if (active.every(function (output) {
      return !output.internal;
    }))
      return "external";
    return "extend";
  }

  function adoptDisplaySnapshot(snapshot) {
    if (!snapshot || !Array.isArray(snapshot.outputs))
      return;

    displays = snapshot.outputs;
    displayProfileAvailable = Boolean(snapshot.profileAvailable);
    const selected = displayOutput(displayPrimary);
    if (!selected || !selected.enabled) {
      const focused = displays.find(function (output) {
        return Boolean(output.focused && output.enabled);
      });
      const active = displays.find(function (output) {
        return Boolean(output.enabled);
      });
      displayPrimary = String((focused || active || displays[0])?.name || "");
    }
    const selectedOutput = displayOutput(displaySelected);
    if (!selectedOutput || !selectedOutput.enabled)
      displaySelected = displayPrimary;
    displayInitialPrimary = displayPrimary;
    rebuildDisplayDraft();
    displaysReady = true;

    if (snapshot.pending && snapshot.pending.token) {
      displayPendingToken = String(snapshot.pending.token);
      displayConfirmSeconds = Math.max(0, Number(snapshot.pending.expiresIn || 0));
      if (displayConfirmSeconds > 0)
        displayConfirmTimer.restart();
    } else if (displayPendingToken.length > 0) {
      displayPendingToken = "";
      displayConfirmSeconds = 0;
      displayConfirmTimer.stop();
    }
  }

  function refreshDisplays() {
    if (displayStatusProc.running) {
      displayRefreshPending = true;
      return;
    }
    displayRefreshPending = false;
    displayStatusProc.output = "";
    displayStatusProc.errorOutput = "";
    displayStatusProc.running = true;
  }

  function finishDisplayRefresh() {
    if (displayRefreshPending) {
      displayRefreshPending = false;
      Qt.callLater(root.refreshDisplays);
    }
  }

  function displayRequest(preset) {
    return {
      preset: preset,
      primary: displayPrimary,
      changes: displayDraft
    };
  }

  function applyDisplayPreset(preset) {
    if (displayOperation.length > 0 || displayPendingToken.length > 0)
      return;
    displayError = "";
    displayOperation = "apply";
    displayApplyProc.output = "";
    displayApplyProc.errorOutput = "";
    displayApplyProc.exec([backend, "display", "apply", JSON.stringify(displayRequest(preset))]);
  }

  function cleanDisplayError(text, fallback) {
    const cleaned = String(text || "").replace(/^jq: error \(at [^)]*\):\s*/m, "").replace(/^desktop-shell:\s*/m, "").trim();
    return cleaned.length > 0 ? cleaned : fallback;
  }

  function keepDisplayLayout() {
    if (displayPendingToken.length === 0 || displayOperation.length > 0)
      return;
    displayOperation = "keep";
    displayDecisionProc.output = "";
    displayDecisionProc.errorOutput = "";
    displayDecisionProc.exec([backend, "display", "keep", displayPendingToken]);
  }

  function revertDisplayLayout() {
    if (displayPendingToken.length === 0 || displayOperation.length > 0)
      return;
    displayOperation = "rollback";
    displayDecisionProc.output = "";
    displayDecisionProc.errorOutput = "";
    displayDecisionProc.exec([backend, "display", "rollback", displayPendingToken]);
  }

  function resetDisplayProfiles() {
    if (displayOperation.length > 0 || displayPendingToken.length > 0)
      return;
    displayError = "";
    displayOperation = "reset";
    displayResetProc.output = "";
    displayResetProc.errorOutput = "";
    displayResetProc.running = true;
  }

  function refreshAll() {
    refreshBluetoothForPage();
    if (brightnessSupported)
      brightnessProc.running = true;
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

  function updateBrightness(value) {
    const raw = String(value).trim();
    if (raw.length === 0 || !isFinite(Number(raw)))
      return;
    const nextValue = clamp(Number(raw) / 100, 0, 1);
    if (brightnessReady && Math.abs(nextValue - brightness) > 0.005)
      showOsd("brightness", nextValue);
    brightness = nextValue;
    brightnessReady = true;
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
    displayRestoreProc.running = true;
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
    if (page === "display" && open)
      refreshDisplays();

    if (!open || !mainSurfaceTransition.presented) {
      pageTransition.stop();
      displayedPage = page;
      pageLoader.opacity = 1;
      pageTranslation.x = 0;
    } else {
      pageDirection = page === "main" ? -1 : 1;
      pageTransition.restart();
    }
  }

  onOpenChanged: {
    if (open) {
      mainInputIntent.claimKeyboard();
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
    if (open && page === "display")
      refreshDisplays();
  }

  Connections {
    target: Hyprland

    function onRawEvent(event) {
      const name = String(event?.name || "");
      if (name === "monitoradded" || name === "monitoraddedv2" || name === "monitorremoved" || name === "monitorremovedv2")
        displayHotplugTimer.restart();
    }
  }

  Timer {
    id: displayHotplugTimer
    interval: 280
    repeat: false
    onTriggered: {
      if (root.displayPendingToken.length > 0 || root.displayOperation.length > 0)
        root.refreshDisplays();
      else
        displayRestoreProc.running = true;
    }
  }

  Timer {
    id: displayRefreshTimer
    interval: 420
    repeat: false
    onTriggered: root.refreshDisplays()
  }

  Timer {
    id: displayConfirmTimer
    interval: 1000
    repeat: true
    onTriggered: {
      root.displayConfirmSeconds = Math.max(0, root.displayConfirmSeconds - 1);
      if (root.displayConfirmSeconds === 0) {
        displayConfirmTimer.stop();
        root.revertDisplayLayout();
      }
    }
  }

  Timer {
    interval: root.bluetoothPollInterval
    running: root.open
    repeat: true
    onTriggered: {
      const now = Date.now();
      if ((root.page === "main" || root.page === "bluetooth") && root.lastBluetoothPollAt > 0 && now - root.lastBluetoothPollAt > root.bluetoothStaleAfter)
        root.handleBluetoothGap();
      root.lastBluetoothPollAt = now;
      root.refreshBluetoothForPage();
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
    font.family: theme.uiFontFamily
    font.pixelSize: 12
    font.bold: true
  }

  Timer {
    interval: 600
    running: true
    onTriggered: volumeReady = true
  }

  PwObjectTracker {
    objects: audioDetailsActive ? Pipewire.nodes.values : [sink, source]
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
    onLoadFailed: function () {
      setText("0");
    }
  }

  FileView {
    id: countFile
    path: stateDir + "/count"
    preload: true
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.updateNotificationCount()
    onLoadFailed: function () {
      setText("0");
    }
  }

  FileView {
    id: focusFile
    path: preferencesDir + "/focus"
    preload: true
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.focusMode = text().trim() === "1"
    onLoadFailed: function () {
      setText("0");
    }
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

    onNotification: function (notification) {
      notification.tracked = true;
      const notificationId = Number(notification.id);
      const policy = root.notificationPolicy(notification);
      const item = {
        id: notificationId,
        notification: notification,
        time: Date.now()
      };
      notification.closed.connect(function () {
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
    onExited: function (exitCode) {
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
    onExited: function (exitCode) {
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
      onRead: function (data) {
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
    onExited: function (exitCode) {
      const wasClosing = root.bluetoothSessionClosing;
      bluetoothSessionStopTimer.stop();
      root.bluetoothSessionClosing = false;
      root.bluetoothSessionActive = false;
      root.stopBluetoothDiscovery();

      if (!wasClosing && root.open && root.page === "bluetooth" && root.bluetoothEnabled)
        root.bluetoothError = root.cleanBluetoothError(output, "Pairing mode ended unexpectedly");
      else if (wasClosing && root.open && root.page === "bluetooth" && root.bluetoothEnabled)
        Qt.callLater(function () {
          root.beginBluetoothSession();
        });
    }
  }

  Process {
    id: bluetoothDiscoveryProc
    command: [backend, "bluetooth", "discover"]
    stdinEnabled: true
    onStarted: bluetoothDiscoveryProc.write("scan on\n")
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function (data) {
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
    onExited: function (exitCode) {
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
    onExited: function (exitCode) {
      const action = root.bluetoothOperation;
      const fallback = action === "pair" ? "Could not pair with this device" : (action === "connect" ? "Could not connect to this device" : (action === "disconnect" ? "Could not disconnect this device" : "Could not forget this device"));
      root.finishBluetoothOperation(exitCode, output, fallback);
    }
  }

  Process {
    id: displayStatusProc
    property string output: ""
    property string errorOutput: ""
    command: root.boundedBackendCommand(["display", "status-json"])
    stdout: StdioCollector {
      onStreamFinished: displayStatusProc.output = text
    }
    stderr: StdioCollector {
      onStreamFinished: displayStatusProc.errorOutput = text
    }
    onExited: function (exitCode) {
      if (exitCode === 0) {
        const snapshot = root.parseJson(output, null);
        if (snapshot)
          root.adoptDisplaySnapshot(snapshot);
      } else if (root.open && root.page === "display") {
        root.displayError = root.cleanDisplayError(errorOutput, "Could not read display state");
      }
      root.finishDisplayRefresh();
    }
  }

  Process {
    id: displayApplyProc
    property string output: ""
    property string errorOutput: ""
    stdout: StdioCollector {
      onStreamFinished: displayApplyProc.output = text
    }
    stderr: StdioCollector {
      onStreamFinished: displayApplyProc.errorOutput = text
    }
    onExited: function (exitCode) {
      if (exitCode === 0) {
        const pending = root.parseJson(output, null);
        if (pending && pending.token) {
          root.displayPendingToken = String(pending.token);
          root.displayConfirmSeconds = Math.max(0, Number(pending.expiresIn || 0));
          displayConfirmTimer.restart();
        }
      } else {
        root.displayError = root.cleanDisplayError(errorOutput, "Could not apply display layout");
      }
      root.displayOperation = "";
      displayRefreshTimer.restart();
    }
  }

  Process {
    id: displayDecisionProc
    property string output: ""
    property string errorOutput: ""
    stdout: StdioCollector {
      onStreamFinished: displayDecisionProc.output = text
    }
    stderr: StdioCollector {
      onStreamFinished: displayDecisionProc.errorOutput = text
    }
    onExited: function (exitCode) {
      if (exitCode !== 0)
        root.displayError = root.cleanDisplayError(errorOutput, "Could not confirm display layout");
      root.displayPendingToken = "";
      root.displayConfirmSeconds = 0;
      displayConfirmTimer.stop();
      root.displayOperation = "";
      displayRefreshTimer.restart();
    }
  }

  Process {
    id: displayRestoreProc
    property string errorOutput: ""
    command: [backend, "display", "restore"]
    stderr: StdioCollector {
      onStreamFinished: displayRestoreProc.errorOutput = text
    }
    onExited: function (exitCode) {
      if (exitCode !== 0 && root.open && root.page === "display")
        root.displayError = root.cleanDisplayError(errorOutput, "Could not restore display profile");
      displayRefreshTimer.restart();
    }
  }

  Process {
    id: displayResetProc
    property string output: ""
    property string errorOutput: ""
    command: [backend, "display", "reset"]
    stdout: StdioCollector {
      onStreamFinished: displayResetProc.output = text
    }
    stderr: StdioCollector {
      onStreamFinished: displayResetProc.errorOutput = text
    }
    onExited: function (exitCode) {
      if (exitCode !== 0)
        root.displayError = root.cleanDisplayError(errorOutput, "Could not restore the startup layout");
      root.displayOperation = "";
      displayRefreshTimer.restart();
    }
  }

  Process {
    id: brightnessProc
    command: [backend, "brightness", "get"]
    stdout: StdioCollector {
      onStreamFinished: root.updateBrightness(text)
    }
  }

  FileView {
    id: brightnessValueFile
    path: root.brightnessBackend === "ddc" && root.brightnessReady ? root.brightnessValuePath : ""
    preload: path.length > 0
    watchChanges: path.length > 0
    onFileChanged: reload()
    onLoaded: root.updateBrightness(text())
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
        root.brightnessValuePath = String(capabilities.valuePath || "");
        if (capabilities.backend === "backlight" || capabilities.backend === "ddc")
          root.brightnessBackend = capabilities.backend;
        if (root.brightnessSupported) {
          brightnessProc.running = true;
          if (root.brightnessBackend === "backlight")
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
      onRead: function (data) {
        root.updateBrightness(data);
      }
    }
    onExited: function (exitCode) {
      if (root.brightnessSupported && root.brightnessBackend === "backlight" && exitCode !== 3)
        brightnessWatchRestartTimer.restart();
    }
  }

  Timer {
    id: brightnessWatchRestartTimer
    interval: 1000
    onTriggered: {
      if (root.brightnessSupported && root.brightnessBackend === "backlight")
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
      setBrightnessProc.exec([backend, "brightness", "set", String(pendingBrightnessPercent)]);
    }
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
    function toggle() {
      root.toggleOpen();
    }
    function open() {
      if (root.open)
        root.refreshAll();
      root.openPanel();
    }
    function wifiPage() {
      const refresh = root.open && root.page === "wifi";
      root.page = "wifi";
      root.openPanel();
      if (refresh)
        root.scanWifi();
    }
    function bluetoothPage() {
      const refresh = root.open && root.page === "bluetooth";
      root.page = "bluetooth";
      root.openPanel();
      if (refresh)
        root.refreshBluetooth(true);
    }
    function audioPage() {
      root.page = "audio";
      root.openPanel();
    }
    function displayPage() {
      root.page = "display";
      root.openPanel();
      root.refreshDisplays();
    }
    function close() {
      root.open = false;
    }
    function dnd() {
      root.toggleDnd();
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "custom" && event.data === "desktop-shell:dismiss-notification-popups")
        root.notificationPopupsCloseRequested();
      else if (event.name === "custom" && event.data === "desktop-shell:dismiss-shell-popup")
        root.open = false;
      else if (event.name === "custom" && event.data === "desktop-shell:control-center:toggle")
        root.toggleOpen();
    }
  }

  BarOverlayWindow {
    id: mainWindow
    barSurface: root.barSurface
    requested: root.open
    presented: mainSurfaceTransition.presented
    surfaceNamespace: "quickshell:controlCenter"

    InputIntent {
      id: mainInputIntent
    }

    Rectangle {
      anchors.fill: parent
      color: theme.surfaceScrim
      opacity: mainSurfaceTransition.progress

      MouseArea {
        anchors.fill: parent
        enabled: root.open
        onClicked: root.open = false
      }

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

        opacity: 0.42 + mainSurfaceTransition.progress * 0.58

        Rectangle {
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          width: 1
          color: theme.borderMuted
        }

        MouseArea {
          anchors.fill: parent
          onClicked: function (mouse) {
            mouse.accepted = true;
          }
        }

        ColumnLayout {
          anchors.fill: parent
          anchors.leftMargin: 20
          anchors.rightMargin: 20
          anchors.topMargin: 20
          anchors.bottomMargin: 16
          spacing: 12
          opacity: Math.max(0, Math.min(1, (mainSurfaceTransition.progress - 0.12) / 0.88))
          transform: Translate {
            // Translate moves pixels without changing layout geometry.
            // qmllint disable Quick.layout-positioning
            x: (1 - mainSurfaceTransition.progress) * 10
            // qmllint enable Quick.layout-positioning
          }

          ControlHeader {
            id: mainHeader
            Layout.fillWidth: true
            pageTitle: root.displayedPage === "audio" ? "Sound" : root.displayedPage === "wifi" ? "Wi-Fi" : (root.displayedPage === "bluetooth" ? "Bluetooth" : (root.displayedPage === "display" ? "Displays" : "Control Center"))
            backVisible: root.displayedPage !== "main"
            onBack: root.page = "main"
          }

          Loader {
            id: pageLoader
            // ColumnLayout owns geometry; page motion only transforms pixels.
            transform: Translate {
              id: pageTranslation
            }
            Layout.fillWidth: true
            Layout.fillHeight: true
            sourceComponent: root.displayedPage === "audio" ? audioPage : root.displayedPage === "wifi" ? wifiPage : (root.displayedPage === "bluetooth" ? bluetoothPage : (root.displayedPage === "display" ? displayPage : mainPage))
          }
        }
      }
    }

    Shortcut {
      sequence: "Esc"
      onActivated: {
        if (root.page !== "main")
          root.page = "main";
        else
          root.open = false;
      }
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
        MotionNumberAnimation {
          role: MotionNumberAnimation.Content
        }
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
    visible: popupSurfaceTransition.presented && !root.open
    color: "transparent"
    exclusiveZone: 0
    WlrLayershell.namespace: "quickshell:notificationPopups"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: popupKeyboardHover.hovered ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

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
        // Translate moves pixels without changing layout geometry.
        // qmllint disable Quick.layout-positioning
        x: (1 - popupSurfaceTransition.progress) * 32
        // qmllint enable Quick.layout-positioning
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
      color: theme.special
      opacity: root.focusBarOpen ? 0.35 : 0.8

      Behavior on height {
        MotionNumberAnimation {
          role: MotionNumberAnimation.FocusTravel
        }
      }
      Behavior on opacity {
        MotionNumberAnimation {
          role: MotionNumberAnimation.Feedback
        }
      }
    }
  }

  Component {
    id: mainPage
    ColumnLayout {
      id: mainContent
      spacing: 10
      QuickControls {
        Layout.fillWidth: true
        controller: root
        colors: theme
        compact: mainContent.height < 600
      }
      RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 8
        Layout.preferredHeight: 32
        Layout.minimumHeight: 32
        Layout.maximumHeight: 32
        spacing: 8
        Text {
          text: "Notifications"
          color: theme.textPrimary
          font.family: theme.uiFontFamily
          font.pixelSize: 15
          font.bold: true
        }
        Item {
          Layout.fillWidth: true
        }
        Text {
          visible: root.notifications.length > 0
          text: root.notifications.length
          color: theme.textMuted
          font.family: theme.uiFontFamily
          font.pixelSize: 10
        }
        ActionButton {
          visible: root.notifications.length > 0
          label: "Clear all"
          flatAction: true
          onClicked: root.clearNotifications()
        }
      }
      RowLayout {
        visible: root.clearedNotifications.length > 0
        Layout.fillWidth: true
        Text {
          Layout.fillWidth: true
          text: root.clearedNotifications.length + " cleared"
          color: theme.textSecondary
          font.family: theme.uiFontFamily
          font.pixelSize: 12
        }
        ActionButton {
          label: "Undo"
          flatAction: true
          onClicked: root.undoClearNotifications()
        }
      }
      Item {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 60
        ListView {
          id: historyList
          objectName: "notificationHistory"
          anchors.fill: parent
          anchors.rightMargin: 6
          clip: true
          spacing: 10
          cacheBuffer: 0
          boundsBehavior: Flickable.StopAtBounds
          model: History.entries(root.notificationGroups(true).concat(root.notificationGroups(false)), root.expandedNotificationGroups)
          delegate: NotificationItem {
            required property var modelData
            width: historyList.width
            item: modelData.item
            group: modelData.group
            firstInGroup: modelData.first
            onDismiss: root.dismissNotification(item.id)
          }
          ScrollBar.vertical: ThemedScrollBar {
            visible: historyList.count > 0 && historyList.contentHeight > historyList.height
          }
        }
        Text {
          anchors.centerIn: parent
          visible: root.notifications.length === 0
          text: "No notifications"
          color: theme.textSecondary
          font.family: theme.uiFontFamily
          font.pixelSize: 13
        }
      }
    }
  }

  Component {
    id: audioPage
    Flickable {
      id: audioScroll
      clip: true
      contentWidth: width
      contentHeight: audioContent.implicitHeight
      boundsBehavior: Flickable.StopAtBounds
      ScrollBar.vertical: ThemedScrollBar {}
      ColumnLayout {
        id: audioContent
        width: audioScroll.width
        spacing: 16
        ShellGroup {
          Layout.fillWidth: true
          colors: theme
          implicitHeight: audioMixer.implicitHeight + 24
          ColumnLayout {
            id: audioMixer
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 12
            spacing: 8
            AudioDeviceSection {
              title: "Output"
              icon: root.sink?.audio?.muted ? "mute" : "speaker"
              current: root.sink
              devices: root.outputDevices
              expanded: root.outputExpanded
              showDivider: false
              accent: theme.info
              onToggleExpanded: root.outputExpanded = !root.outputExpanded
              onVolumeChanged: value => root.setNodeVolume(root.sink, value)
              onToggleMute: root.toggleNodeMute(root.sink)
              onChoose: node => {
                Pipewire.preferredDefaultAudioSink = node;
                root.outputExpanded = false;
              }
            }
            AudioDeviceSection {
              title: "Input"
              icon: root.source?.audio?.muted ? "mic-off" : "mic"
              current: root.source
              devices: root.inputDevices
              expanded: root.inputExpanded
              accent: theme.special
              onToggleExpanded: root.inputExpanded = !root.inputExpanded
              onVolumeChanged: value => root.setNodeVolume(root.source, value)
              onToggleMute: root.toggleNodeMute(root.source)
              onChoose: node => {
                Pipewire.preferredDefaultAudioSource = node;
                root.inputExpanded = false;
              }
            }
          }
        }
        Section {
          title: "Applications"
          visible: root.appStreams.length > 0
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
        Text {
          visible: root.appStreams.length === 0
          Layout.fillWidth: true
          text: "No applications are playing or recording audio"
          color: theme.textSecondary
          font.family: theme.uiFontFamily
          font.pixelSize: 12
          wrapMode: Text.Wrap
        }
      }
    }
  }

  Component {
    id: displayPage
    Flickable {
      id: displayScroll
      clip: true
      contentWidth: width
      contentHeight: displayContent.implicitHeight
      boundsBehavior: Flickable.StopAtBounds
      ScrollBar.vertical: ThemedScrollBar {
        parent: displayScroll.parent
        visible: displayScroll.visible
        anchors.top: displayScroll.top
        anchors.left: displayScroll.right
        anchors.leftMargin: 7
        anchors.bottom: displayScroll.bottom
      }

      ColumnLayout {
        id: displayContent
        width: displayScroll.width
        spacing: 12

        Rectangle {
          Layout.fillWidth: true
          implicitHeight: 68
          visible: root.displayPendingToken.length > 0
          radius: 9
          color: Qt.alpha(theme.warning, 0.12)
          border.color: Qt.alpha(theme.warning, 0.56)
          border.width: 1

          RowLayout {
            id: displayConfirmContent
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            ShellSymbol {
              symbol: "󰍹"
              tint: theme.warning
              size: 18
              Layout.preferredWidth: 24
            }

            ColumnLayout {
              Layout.fillWidth: true
              spacing: 2
              Text {
                Layout.fillWidth: true
                text: "Testing this layout"
                color: theme.textPrimary
                font.family: theme.uiFontFamily
                font.pixelSize: 12
                font.bold: true
              }
              Text {
                Layout.fillWidth: true
                text: "Reverting in " + root.displayConfirmSeconds + " seconds"
                color: theme.textSecondary
                font.family: theme.uiFontFamily
                font.pixelSize: 10
              }
            }

            ActionButton {
              label: "Revert"
              enabled: root.displayOperation.length === 0
              onClicked: root.revertDisplayLayout()
            }
            ActionButton {
              label: "Keep"
              active: true
              enabled: root.displayOperation.length === 0
              onClicked: root.keepDisplayLayout()
            }
          }
        }

        Text {
          Layout.fillWidth: true
          visible: root.displayError.length > 0
          text: root.displayError
          color: theme.danger
          font.family: theme.uiFontFamily
          font.pixelSize: 11
          wrapMode: Text.Wrap
        }

        Item {
          Layout.fillWidth: true
          implicitHeight: displayEditor.implicitHeight

          ColumnLayout {
            id: displayEditor
            width: parent.width
            spacing: 12
            opacity: root.displayEditorLocked ? 0.34 : 1
            enabled: !root.displayEditorLocked

            RowLayout {
              Layout.fillWidth: true
              spacing: 8

              Text {
                Layout.fillWidth: true
                text: "Arrangement"
                color: theme.textMuted
                font.family: theme.uiFontFamily
                font.pixelSize: 12
                font.bold: true
              }

              IconButton {
                glyph: ""
                onClicked: root.refreshDisplays()
              }
            }

            Text {
              Layout.fillWidth: true
              visible: !root.displaysReady
              text: "Detecting displays…"
              color: theme.textSecondary
              font.family: theme.uiFontFamily
              font.pixelSize: 11
            }

            Text {
              Layout.fillWidth: true
              visible: root.displaysReady && root.displays.length === 0
              text: "No connected displays"
              color: theme.textSecondary
              font.family: theme.uiFontFamily
              font.pixelSize: 11
            }

            DisplayArrangement {
              colors: theme
              draft: root.displayDraft
              Layout.fillWidth: true
              visible: root.displays.length > 0
              outputs: root.displays
              selectedName: root.displaySelected
              onSelected: function (name) {
                root.displaySelected = name;
              }
              onMoved: function (name, x, y) {
                root.moveDisplayDraft(name, x, y);
              }
            }

            Section {
              title: "Layout"
              visible: root.displays.length > 1

              Rectangle {
                Layout.fillWidth: true
                implicitHeight: 36
                radius: 8
                clip: true
                color: theme.surfaceMuted
                border.color: theme.borderSubtle
                border.width: 1

                RowLayout {
                  anchors.fill: parent
                  spacing: 0

                  Repeater {
                    model: [
                      {
                        id: "extend",
                        label: "Extend",
                        available: true
                      },
                      {
                        id: "duplicate",
                        label: "Duplicate",
                        available: root.displays.length > 1
                      },
                      {
                        id: "internal",
                        label: "Internal",
                        available: root.displays.some(function (output) {
                          return Boolean(output.internal);
                        })
                      },
                      {
                        id: "external",
                        label: "External",
                        available: root.displays.some(function (output) {
                          return !output.internal;
                        })
                      }
                    ]

                    delegate: ActionButton {
                      required property var modelData
                      Layout.fillWidth: true
                      Layout.fillHeight: true
                      enabled: Boolean(modelData.available)
                      label: modelData.label
                      active: root.displayCurrentPreset() === modelData.id
                      checkable: true
                      checked: active
                      Accessible.role: Accessible.RadioButton
                      onClicked: root.applyDisplayPreset(modelData.id)
                    }
                  }
                }
              }
            }

            DisplayOutputInspector {
              Layout.fillWidth: true
              visible: root.selectedDisplayOutput() !== null
              output: root.selectedDisplayOutput()
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: 8

              ActionButton {
                visible: root.displayProfileAvailable
                label: "Reset layout"
                onClicked: root.resetDisplayProfiles()
              }
              Item {
                Layout.fillWidth: true
              }

              ActionButton {
                label: "Test changes"
                active: true
                enabled: root.displays.length > 0 && root.displayHasChanges
                onClicked: root.applyDisplayPreset("custom")
              }
            }
          }

          Rectangle {
            anchors.fill: parent
            visible: root.displayEditorLocked
            z: 3
            color: "transparent"

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.ForbiddenCursor
            }
          }
        }
      }
    }
  }

  Component {
    id: wifiPage
    ColumnLayout {
      spacing: 14
      RowLayout {
        Layout.fillWidth: true
        implicitHeight: 48
        spacing: 12
        ShellSymbol {
          symbol: "wifi"
          tint: root.wifiEnabled ? theme.info : theme.textMuted
          size: 24
          Layout.preferredWidth: 24
          Layout.preferredHeight: 24
          Layout.alignment: Qt.AlignVCenter
        }
        ColumnLayout {
          Layout.fillWidth: true
          spacing: 3
          Text {
            text: root.wifiEnabled ? "On" : "Off"
            color: theme.textPrimary
            font.family: theme.uiFontFamily
            font.pixelSize: 14
            font.bold: true
          }
          Text {
            Layout.fillWidth: true
            text: root.wifiConnected ? "Connected to " + root.wifiHeaderTitle() : root.wifiHeaderSubtitle()
            color: theme.textSecondary
            font.family: theme.uiFontFamily
            font.pixelSize: 11
            elide: Text.ElideRight
          }
        }
        RadioSwitch {
          Accessible.name: "Wi-Fi radio"
          checked: root.wifiEnabled
          accent: theme.info
          enabled: root.wifiToggleAvailable
          onClicked: root.toggleWifi()
        }
      }
      Rectangle {
        Layout.fillWidth: true
        implicitHeight: 1
        color: theme.borderMuted
      }
      ConnectivityError {
        Layout.fillWidth: true
        visible: root.wifiError.length > 0
        message: root.wifiError
        onDismiss: root.wifiError = ""
      }
      RowLayout {
        Layout.fillWidth: true
        visible: root.wifiAdapterAvailable()
        Text {
          text: "Networks"
          color: theme.textPrimary
          font.family: theme.uiFontFamily
          font.pixelSize: 13
          font.bold: true
        }
        Item {
          Layout.fillWidth: true
        }
        Text {
          text: root.wifiNetworks.length + " available"
          color: theme.textMuted
          font.family: theme.uiFontFamily
          font.pixelSize: 10
        }
        IconButton {
          glyph: "refresh"
          tooltip: "Refresh Wi-Fi networks"
          flatAction: true
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
          ScrollBar.vertical: ThemedScrollBar {}
          ColumnLayout {
            id: wifiContent
            width: wifiScroll.width - 6
            spacing: 0
            Repeater {
              model: root.wifiNetworks
              delegate: WifiNetworkRow {
                required property var modelData
                network: modelData
              }
            }
          }
        }
        ConnectivityEmpty {
          anchors.centerIn: parent
          width: Math.min(parent.width - 32, 310)
          visible: !wifiScroll.visible
          glyph: "wifi"
          accent: theme.info
          title: !wifi.backendAvailable ? "Network service unavailable" : !wifi.hardwareEnabled || !wifi.device ? "Wi-Fi is unavailable" : !root.wifiEnabled ? "Wi-Fi is off" : "Looking for networks"
          message: !wifi.backendAvailable ? "NetworkManager did not provide a networking backend." : !wifi.hardwareEnabled || !wifi.device ? "No wireless adapter is ready." : !root.wifiEnabled ? "Turn it on to discover nearby networks." : "Nearby networks will appear automatically."
          showAction: wifi.backendAvailable && wifi.hardwareEnabled && wifi.device !== null
          actionLabel: root.wifiEnabled ? "Refresh scan" : "Turn on Wi-Fi"
          actionGlyph: root.wifiEnabled ? "refresh" : "wifi"
          actionEnabled: !root.wifiBusy
          onTriggered: root.wifiEnabled ? root.scanWifi() : root.toggleWifi()
        }
      }
    }
  }

  Component {
    id: bluetoothPage
    ColumnLayout {
      spacing: 14
      RowLayout {
        Layout.fillWidth: true
        implicitHeight: 48
        spacing: 12
        ShellSymbol {
          symbol: "bluetooth"
          tint: root.bluetoothEnabled ? theme.special : theme.textMuted
          size: 24
          Layout.preferredWidth: 24
          Layout.preferredHeight: 24
          Layout.alignment: Qt.AlignVCenter
        }
        ColumnLayout {
          Layout.fillWidth: true
          spacing: 3
          Text {
            text: !root.bluetoothStatusReady ? "Checking…" : root.bluetoothEnabled ? "On" : "Off"
            color: theme.textPrimary
            font.family: theme.uiFontFamily
            font.pixelSize: 14
            font.bold: true
          }
          Text {
            Layout.fillWidth: true
            text: root.bluetoothHeaderSubtitle()
            color: theme.textSecondary
            font.family: theme.uiFontFamily
            font.pixelSize: 11
            elide: Text.ElideRight
          }
        }
        RadioSwitch {
          Accessible.name: "Bluetooth radio"
          checked: root.bluetoothEnabled
          busy: root.bluetoothOperation === "enable" || root.bluetoothOperation === "disable"
          accent: theme.special
          enabled: root.bluetoothStatusReady && root.bluetoothAvailable && !root.bluetoothBusy
          onClicked: root.toggleBluetooth()
        }
      }
      Rectangle {
        Layout.fillWidth: true
        implicitHeight: 1
        color: theme.borderMuted
      }
      ConnectivityError {
        Layout.fillWidth: true
        visible: root.bluetoothError.length > 0
        message: root.bluetoothError
        onDismiss: root.bluetoothError = ""
      }
      RowLayout {
        Layout.fillWidth: true
        visible: root.bluetoothEnabled && root.bluetoothAvailable
        spacing: 8
        ShellSymbol {
          symbol: root.bluetoothDiscoverable ? "eye" : "eye-off"
          tint: theme.special
          size: 16
        }
        Text {
          Layout.fillWidth: true
          text: root.bluetoothDiscoverable ? "Visible to nearby devices while this page is open" : "Paired devices can still reconnect"
          color: theme.textSecondary
          font.family: theme.uiFontFamily
          font.pixelSize: 11
          wrapMode: Text.WordWrap
        }
        IconButton {
          glyph: "refresh"
          tooltip: "Restart Bluetooth discovery"
          flatAction: true
          accent: theme.special
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
          ScrollBar.vertical: ThemedScrollBar {}
          ColumnLayout {
            id: bluetoothContent
            width: bluetoothScroll.width - 6
            spacing: 0
            Text {
              Layout.fillWidth: true
              Layout.topMargin: 4
              Layout.bottomMargin: 6
              visible: root.bluetoothPairedDevices().length > 0
              text: "My devices"
              color: theme.textPrimary
              font.family: theme.uiFontFamily
              font.pixelSize: 13
              font.bold: true
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
              Layout.topMargin: root.bluetoothPairedDevices().length > 0 ? 20 : 4
              Layout.bottomMargin: 6
              visible: root.bluetoothNearbyDevices().length > 0
              text: "Nearby devices"
              color: theme.textPrimary
              font.family: theme.uiFontFamily
              font.pixelSize: 13
              font.bold: true
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
        ConnectivityEmpty {
          anchors.centerIn: parent
          width: Math.min(parent.width - 32, 310)
          visible: !bluetoothScroll.visible
          glyph: "bluetooth"
          accent: theme.special
          title: !root.bluetoothStatusReady ? "Checking Bluetooth" : !root.bluetoothAvailable ? "Bluetooth is unavailable" : !root.bluetoothEnabled ? "Bluetooth is off" : !root.bluetoothDevicesReady ? "Looking for devices" : "No devices found"
          message: !root.bluetoothStatusReady ? "Reading the current BlueZ state…" : !root.bluetoothAvailable ? "No controller is ready on this system." : !root.bluetoothEnabled ? "Turn it on to reconnect paired devices or add a new one." : "Put the accessory in pairing mode. It will appear here automatically."
          showAction: root.bluetoothStatusReady && root.bluetoothAvailable
          actionLabel: root.bluetoothEnabled ? "Scan again" : "Turn on Bluetooth"
          actionGlyph: root.bluetoothEnabled ? "refresh" : "bluetooth"
          actionEnabled: !root.bluetoothBusy
          onTriggered: root.bluetoothEnabled ? root.refreshBluetooth(true) : root.toggleBluetooth()
        }
      }
    }
  }

  component ConnectivityError: RowLayout {
    id: connectivityError
    property string message: ""
    signal dismiss
    spacing: 8
    ShellSymbol {
      symbol: "warning"
      tint: theme.danger
      size: 18
    }
    Text {
      Layout.fillWidth: true
      text: connectivityError.message
      color: theme.textPrimary
      font.family: theme.uiFontFamily
      font.pixelSize: 11
      wrapMode: Text.WordWrap
    }
    IconButton {
      glyph: "close"
      tooltip: "Dismiss connectivity error"
      flatAction: true
      onClicked: connectivityError.dismiss()
    }
  }

  component ConnectivityEmpty: ColumnLayout {
    id: empty
    property string glyph
    property string title
    property string message
    property color accent
    property bool showAction: false
    property string actionLabel
    property string actionGlyph
    property bool actionEnabled: true
    signal triggered
    spacing: 10
    ShellSymbol {
      Layout.alignment: Qt.AlignHCenter
      symbol: empty.glyph
      tint: empty.accent
      size: 32
    }
    Text {
      Layout.fillWidth: true
      text: empty.title
      color: theme.textPrimary
      font.family: theme.uiFontFamily
      font.pixelSize: 15
      font.bold: true
      horizontalAlignment: Text.AlignHCenter
    }
    Text {
      Layout.fillWidth: true
      text: empty.message
      color: theme.textSecondary
      font.family: theme.uiFontFamily
      font.pixelSize: 12
      wrapMode: Text.WordWrap
      horizontalAlignment: Text.AlignHCenter
    }
    ActionButton {
      Layout.alignment: Qt.AlignHCenter
      visible: empty.showAction
      label: empty.actionLabel
      glyph: empty.actionGlyph
      enabled: empty.actionEnabled
      onClicked: empty.triggered()
    }
  }

  component Section: ColumnLayout {
    property string title
    property color accent: theme.accent
    Layout.fillWidth: true
    spacing: 8
    Text {
      text: parent.title
      color: theme.textPrimary
      font.family: theme.uiFontFamily
      font.pixelSize: 13
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
      color: theme.accent
      opacity: 0.72
    }

    Behavior on opacity {
      MotionNumberAnimation {
        role: MotionNumberAnimation.Feedback
      }
    }
  }

  component ControlHeader: Item {
    id: header
    property string pageTitle
    property bool backVisible: false
    signal back
    function focusDefault() {
      (backVisible ? backButton : closeButton).forceActiveFocus(Qt.TabFocusReason);
    }
    implicitHeight: 36
    RowLayout {
      anchors.fill: parent
      spacing: 10
      IconButton {
        id: backButton
        visible: header.backVisible
        glyph: "back"
        tooltip: "Back to Control Center"
        flatAction: true
        onClicked: header.back()
      }
      Text {
        Layout.fillWidth: true
        text: header.pageTitle
        color: theme.textPrimary
        font.family: theme.uiFontFamily
        font.pixelSize: 20
        font.bold: true
        elide: Text.ElideRight
      }
      IconButton {
        id: closeButton
        glyph: "close"
        tooltip: "Close Control Center"
        onClicked: root.open = false
      }
    }
  }

  component StatusLabel: Text {
    property string glyph: ""
    property string label
    property bool active: false
    property color accent: theme.accent
    text: label
    color: theme.textSecondary
    font.family: theme.uiFontFamily
    font.pixelSize: 10
  }

  component ActionButton: ShellButton {
    colors: theme
  }
  component IconButton: ShellButton {
    colors: theme
    implicitWidth: 32
    implicitHeight: 32
  }
  component RadioSwitch: ShellSwitch {
    colors: theme
  }

  component GainValueBadge: Rectangle {
    id: gainBadge
    property real value: 0
    property bool muted: false
    readonly property bool boosted: value > 1.005
    implicitWidth: gainText.implicitWidth + (boosted ? 14 : 0)
    implicitHeight: 22
    radius: 7
    color: boosted ? Qt.alpha(theme.caution, 0.14) : "transparent"
    border.color: boosted ? Qt.alpha(theme.caution, 0.48) : "transparent"
    border.width: 1
    opacity: muted ? 0.52 : 1

    Text {
      id: gainText
      anchors.centerIn: parent
      text: (gainBadge.boosted ? "Boost " : "") + Math.round(gainBadge.value * 100) + "%"
      color: gainBadge.boosted ? theme.caution : theme.textSecondary
      font.family: theme.uiFontFamily
      font.pixelSize: gainBadge.boosted ? 9 : 11
      font.bold: gainBadge.boosted
    }
  }

  component GainSlider: ShellSlider {
    colors: theme
  }

  component Bar: Rectangle {
    property real value: 0
    property color accent: theme.accent
    implicitHeight: 8
    radius: 4
    color: theme.surfaceMuted
    Rectangle {
      width: parent.width * root.clamp(parent.value, 0, 1)
      height: parent.height
      radius: parent.radius
      color: parent.accent

      Behavior on width {
        MotionNumberAnimation {
          role: MotionNumberAnimation.FocusTravel
        }
      }
      Behavior on color {
        MotionColorAnimation {
          role: MotionNumberAnimation.Content
        }
      }
    }
  }

  component OsdRow: RowLayout {
    id: osdRow
    property string icon: ""
    property real level: 0
    property string label: ""
    property color accent: theme.accent
    spacing: 12

    ShellSymbol {
      symbol: osdRow.icon
      tint: osdRow.accent
      size: 17
      Layout.preferredWidth: 28
    }
    Bar {
      Layout.fillWidth: true
      value: osdRow.level
      accent: osdRow.accent
    }
    Text {
      text: osdRow.label
      color: theme.textSecondary
      font.family: theme.uiFontFamily
      font.pixelSize: 12
      horizontalAlignment: Text.AlignRight
      Layout.preferredWidth: 38
    }
  }

  component DisplayOutputInspector: Item {
    id: displayInspector
    required property var output
    readonly property var modes: output?.availableModes && output.availableModes.length > 0 ? output.availableModes : ["preferred"]
    readonly property string selectedMode: String(root.displayDraftValue(output?.name, "mode", output?.mode || "preferred"))
    readonly property real selectedScale: Number(root.displayDraftValue(output?.name, "scale", output?.scale || 1))

    implicitHeight: displayInspectorContent.implicitHeight

    ColumnLayout {
      id: displayInspectorContent
      width: parent.width
      spacing: 0

      RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 52
        spacing: 9

        ShellSymbol {
          symbol: displayInspector.output?.internal ? "󰌢" : "󰍹"
          tint: theme.info
          size: 18
          Layout.preferredWidth: 24
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 1

          Text {
            Layout.fillWidth: true
            text: root.displayName(displayInspector.output)
            color: theme.textPrimary
            font.family: theme.uiFontFamily
            font.pixelSize: 12
            font.bold: true
            elide: Text.ElideRight
          }

          Text {
            Layout.fillWidth: true
            text: String(displayInspector.output?.name || "")
            color: theme.textSecondary
            font.family: theme.uiFontFamily
            font.pixelSize: 9
          }
        }

        Text {
          visible: root.displays.length > 1 && root.displayPrimary === String(displayInspector.output?.name || "")
          text: "Primary"
          color: theme.info
          font.family: theme.uiFontFamily
          font.pixelSize: 9
          font.bold: true
        }

        IconButton {
          visible: root.displays.length > 1
          glyph: root.displayPrimary === String(displayInspector.output?.name || "") ? "" : ""
          tooltip: root.displayPrimary === String(displayInspector.output?.name || "") ? "" : "Set as primary display"
          active: root.displayPrimary === String(displayInspector.output?.name || "")
          accent: theme.info
          onClicked: root.displayPrimary = String(displayInspector.output?.name || "")
        }
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: theme.borderSubtle
        opacity: 0.72
      }

      RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 52
        spacing: 10

        Text {
          text: "Mode"
          color: theme.textMuted
          font.family: theme.uiFontFamily
          font.pixelSize: 10
          Layout.preferredWidth: 48
        }

        ComboBox {
          id: displayModeBox
          Accessible.name: "Display mode for " + String(displayInspector.output?.name || "")
          Layout.fillWidth: true
          model: displayInspector.modes
          currentIndex: {
            for (let i = 0; i < displayInspector.modes.length; i++) {
              if (String(displayInspector.modes[i]) === displayInspector.selectedMode)
                return i;
            }
            return 0;
          }
          onActivated: function (index) {
            root.setDisplayDraftValue(String(displayInspector.output?.name || ""), "mode", String(displayInspector.modes[index]));
          }
          Keys.onPressed: event => {
            if (event.key === Qt.Key_Up || event.key === Qt.Key_Down || event.key === Qt.Key_PageUp || event.key === Qt.Key_PageDown || event.key === Qt.Key_Home || event.key === Qt.Key_End)
              mainInputIntent.claimKeyboard();
          }

          contentItem: Text {
            leftPadding: 10
            rightPadding: 28
            text: root.displayModeLabel(displayModeBox.displayText)
            color: theme.textSecondary
            font.family: theme.uiFontFamily
            font.pixelSize: 10
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
          }
          indicator: ShellSymbol {
            symbol: "down"
            size: 12
            tint: theme.textSecondary
            x: displayModeBox.width - width - 10
            y: (displayModeBox.height - height) / 2
          }
          background: Rectangle {
            implicitHeight: 34
            radius: 6
            color: displayModeBox.hovered ? theme.surfaceMutedHover : theme.surfaceMuted
            border.color: displayModeBox.activeFocus ? theme.info : theme.borderSubtle
            border.width: 1
          }
          delegate: ItemDelegate {
            required property var modelData
            width: displayModeBox.width
            // Keep Qt's delegate hover from rewriting keyboard highlightedIndex.
            hoverEnabled: false
            contentItem: Text {
              text: root.displayModeLabel(modelData)
              color: theme.textSecondary
              font.family: theme.uiFontFamily
              font.pixelSize: 10
              verticalAlignment: Text.AlignVCenter
            }
            background: Rectangle {
              color: highlighted || (mainInputIntent.pointerActive && displayModeHover.hovered) ? theme.surfaceMutedHover : theme.bgSolid
            }
            HoverHandler {
              id: displayModeHover
              blocking: false
            }
          }
          popup: Popup {
            y: displayModeBox.height + 2
            width: displayModeBox.width
            implicitHeight: Math.min(230, contentItem.implicitHeight + 2)
            padding: 1
            contentItem: ListView {
              clip: true
              implicitHeight: contentHeight
              model: displayModeBox.popup.visible ? displayModeBox.delegateModel : null
              currentIndex: displayModeBox.highlightedIndex
              Keys.onPressed: event => {
                if (event.key === Qt.Key_Up || event.key === Qt.Key_Down || event.key === Qt.Key_PageUp || event.key === Qt.Key_PageDown || event.key === Qt.Key_Home || event.key === Qt.Key_End)
                  mainInputIntent.claimKeyboard();
              }
              ScrollIndicator.vertical: ScrollIndicator {}
            }
            background: Rectangle {
              radius: 7
              color: theme.bgSolid
              border.color: theme.borderSubtle
              border.width: 1
            }
          }
        }
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: theme.borderSubtle
        opacity: 0.72
      }

      RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 48
        spacing: 8

        Text {
          text: "Scale"
          color: theme.textMuted
          font.family: theme.uiFontFamily
          font.pixelSize: 10
          Layout.preferredWidth: 48
        }

        GainSlider {
          Accessible.name: "Display scale for " + String(displayInspector.output?.name || "")
          Layout.fillWidth: true
          from: 0.5
          to: 3
          stepSize: 0.25
          value: displayInspector.selectedScale
          accent: theme.info
          onMoved: root.setDisplayDraftValue(String(displayInspector.output?.name || ""), "scale", value)
        }

        Text {
          text: Math.round(displayInspector.selectedScale * 100) + "%"
          color: theme.textSecondary
          font.family: theme.uiFontFamily
          font.pixelSize: 10
          horizontalAlignment: Text.AlignRight
          Layout.preferredWidth: 38
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
    property color accent: theme.accent
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
          glyph: audioSection.icon
          accent: audioSection.current?.audio?.muted ? theme.danger : theme.info
          active: false
          tooltip: (audioSection.current?.audio?.muted ? "Unmute " : "Mute ") + audioSection.title.toLowerCase()
          onClicked: audioSection.toggleMute()
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 2
          Text {
            Layout.fillWidth: true
            text: audioSection.title
            color: theme.textMuted
            font.family: theme.uiFontFamily
            font.pixelSize: 11
            font.bold: true
            elide: Text.ElideRight
          }
          Text {
            Layout.fillWidth: true
            text: root.deviceName(audioSection.current)
            color: theme.textPrimary
            font.family: theme.uiFontFamily
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
          glyph: audioSection.expanded ? "" : ""
          tooltip: (audioSection.expanded ? "Hide " : "Show ") + audioSection.title.toLowerCase() + " devices"
          onClicked: audioSection.toggleExpanded()
        }
      }

      GainSlider {
        Accessible.name: audioSection.title + " volume for " + root.deviceName(audioSection.current)
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
            glyph: audioSection.title === "Input" ? "" : ""
            node: modelData
            active: modelData === audioSection.current
            accent: audioSection.accent
            onClicked: audioSection.choose(modelData)
          }
        }
      }
    }
  }

  component DeviceChoiceRow: Button {
    id: deviceRow
    property string glyph
    property var node
    property bool active: false
    property color accent: theme.info
    Layout.fillWidth: true
    implicitHeight: 46
    focusPolicy: Qt.StrongFocus
    Accessible.name: root.deviceName(node)
    Accessible.role: Accessible.RadioButton
    Accessible.checked: active
    background: Rectangle {
      radius: theme.controlRadius
      color: deviceRow.active ? theme.selectedBg : deviceRow.hovered ? theme.bgHover : "transparent"
      border.color: theme.accent
      border.width: deviceRow.visualFocus ? 2 : 0
    }

    RowLayout {
      anchors.fill: parent
      anchors.margins: 10
      spacing: 10
      ShellSymbol {
        Layout.preferredWidth: 24
        symbol: deviceRow.glyph
        tint: deviceRow.active ? deviceRow.accent : theme.textPrimary
        size: 15
      }
      Text {
        Layout.fillWidth: true
        text: root.deviceName(deviceRow.node)
        color: theme.textSecondary
        font.family: theme.uiFontFamily
        font.pixelSize: 11
        elide: Text.ElideRight
      }
      ShellSymbol {
        symbol: deviceRow.active ? "" : ""
        tint: deviceRow.accent
        size: 13
        Layout.preferredWidth: 18
      }
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

          ShellSymbol {
            anchors.centerIn: parent
            symbol: root.streamIcon(node)
            tint: row.accent
            size: 13
          }
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 1

          Text {
            Layout.fillWidth: true
            text: root.streamName(node)
            color: theme.textPrimary
            font.family: theme.uiFontFamily
            font.pixelSize: 11
            font.bold: true
            elide: Text.ElideRight
          }
          Text {
            Layout.fillWidth: true
            text: root.streamSubtitle(node)
            color: theme.textMuted
            font.family: theme.uiFontFamily
            font.pixelSize: 9
            elide: Text.ElideRight
          }
        }

        GainValueBadge {
          value: row.streamVolume
          muted: row.streamMuted
        }

        IconButton {
          glyph: row.streamMuted ? "󰝟" : ""
          accent: row.streamMuted ? theme.danger : theme.info
          tooltip: (row.streamMuted ? "Unmute " : "Mute ") + root.streamName(node)
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
        Accessible.name: "Volume for " + root.streamName(node)
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

  component NotificationVisual: Rectangle {
    id: notificationVisual
    property var notification
    property real visualSize: 28
    property string fallbackIcon: root.notificationIsCritical(notification) ? "" : ""
    property color accent: root.notificationIsCritical(notification) ? theme.danger : theme.info

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

    ShellSymbol {
      anchors.centerIn: parent
      visible: !notificationImage.visible
      symbol: notificationVisual.fallbackIcon
      tint: notificationVisual.accent
      size: Math.max(12, notificationVisual.visualSize * 0.7)
    }
  }

  component NotificationProgress: ColumnLayout {
    id: notificationProgress
    property var progressData: ({
        visible: false,
        value: 0,
        text: ""
      })

    Layout.fillWidth: true
    visible: Boolean(progressData?.visible)
    spacing: 4

    RowLayout {
      Layout.fillWidth: true
      Text {
        Layout.fillWidth: true
        text: "Progress"
        color: theme.textMuted
        font.family: theme.uiFontFamily
        font.pixelSize: 9
      }
      Text {
        text: notificationProgress.progressData?.text || ""
        color: theme.textSecondary
        font.family: theme.uiFontFamily
        font.pixelSize: 9
      }
    }

    Bar {
      Layout.fillWidth: true
      value: Number(notificationProgress.progressData?.value || 0)
      accent: theme.info
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
      color: theme.textSecondary
      placeholderTextColor: theme.textMuted
      font.family: theme.uiFontFamily
      font.pixelSize: 11
      selectByMouse: true
      onAccepted: inlineReply.submit()

      background: Rectangle {
        radius: 8
        color: theme.surfaceMuted
        border.color: replyField.activeFocus ? theme.accent : theme.borderMuted
        border.width: 1
      }
    }

    ActionButton {
      label: "Send"
      maximumWidth: 82
      enabled: replyField.text.trim().length > 0
      onClicked: inlineReply.submit()
    }
  }

  component NotificationItem: Rectangle {
    id: notifRow
    property var item
    property var group: ({})
    property bool firstInGroup: true
    readonly property var notification: root.itemNotification(item)
    readonly property var actions: root.visibleNotificationActions(notification)
    readonly property string bodyText: root.sanitizeNotificationBody(notification?.body || "")
    readonly property bool hasBody: bodyText.length > 0 && bodyText !== "."
    readonly property var progressData: root.notificationProgress(notification)
    readonly property bool hasDefaultAction: root.defaultNotificationAction(notification) !== null
    activeFocusOnTab: hasDefaultAction
    Accessible.role: hasDefaultAction ? Accessible.Button : Accessible.StaticText
    Accessible.name: root.notificationAppName(notification) + ": " + (notification?.summary || "Notification")
    Accessible.onPressAction: root.invokeDefaultNotificationAction(notification)
    Keys.onSpacePressed: event => {
      event.accepted = hasDefaultAction;
      if (hasDefaultAction)
        root.invokeDefaultNotificationAction(notification);
    }
    Keys.onReturnPressed: event => {
      event.accepted = hasDefaultAction;
      if (hasDefaultAction)
        root.invokeDefaultNotificationAction(notification);
    }
    signal dismiss
    Layout.fillWidth: true
    implicitHeight: Math.max(100, notifColumn.implicitHeight + 24)
    radius: theme.groupRadius
    color: theme.surfaceRaised
    border.color: activeFocus ? theme.accent : theme.borderMuted
    border.width: activeFocus ? 2 : 1

    MouseArea {
      anchors.fill: parent
      enabled: notifRow.hasDefaultAction
      hoverEnabled: enabled
      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: root.invokeDefaultNotificationAction(notifRow.notification)
    }

    ColumnLayout {
      id: notifColumn
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: 12
      spacing: 7
      RowLayout {
        Layout.fillWidth: true
        spacing: 8
        NotificationVisual {
          notification: notifRow.notification
          visualSize: 20
          Layout.preferredWidth: 20
          Layout.preferredHeight: 20
        }
        Text {
          Layout.fillWidth: true
          text: root.notificationAppName(notifRow.notification)
          color: theme.textPrimary
          font.family: theme.uiFontFamily
          font.pixelSize: 10
          font.bold: true
          elide: Text.ElideRight
        }
        Text {
          text: root.relativeNotificationTime(notifRow.item?.time || 0)
          color: theme.textMuted
          font.family: theme.uiFontFamily
          font.pixelSize: 9
        }
        IconButton {
          glyph: "close"
          tooltip: "Dismiss notification"
          flatAction: true
          onClicked: notifRow.dismiss()
        }
      }
      Text {
        Layout.fillWidth: true
        text: notifRow.notification?.summary || "Notification"
        color: theme.textPrimary
        font.family: theme.uiFontFamily
        font.pixelSize: 13
        font.bold: true
        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
      }
      Text {
        Layout.fillWidth: true
        visible: notifRow.hasBody
        text: notifRow.bodyText
        textFormat: Text.StyledText
        linkColor: theme.accent
        color: theme.textSecondary
        font.family: theme.uiFontFamily
        font.pixelSize: 12
        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
        maximumLineCount: 4
        elide: Text.ElideRight
        onLinkActivated: function (link) {
          root.openNotificationLink(link);
        }
      }
      NotificationProgress {
        progressData: notifRow.progressData
      }
      NotificationInlineReply {
        notification: notifRow.notification
      }
      Flow {
        Layout.fillWidth: true
        Layout.preferredHeight: implicitHeight
        visible: notifRow.actions.length > 0
        spacing: 6
        Repeater {
          model: root.actionEntries(notifRow.actions, notifRow.notification)
          delegate: ActionButton {
            required property var modelData
            maximumWidth: notifRow.width - 24
            flatAction: true
            label: root.actionLabel(modelData.action)
            imageSource: root.notificationActionIconSource(modelData.notification, modelData.action)
            onClicked: root.invokeNotificationAction(modelData.action)
          }
        }
      }
      ActionButton {
        visible: notifRow.firstInGroup && (notifRow.group?.items?.length || 0) > 1
        label: root.notificationGroupExpanded(notifRow.group.key) ? "Show less" : "Show " + (notifRow.group.items.length - 1) + " older"
        flatAction: true
        onClicked: root.toggleNotificationGroup(notifRow.group.key)
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
      MotionNumberAnimation {
        role: MotionNumberAnimation.FocusTravel
      }
    }

    Component.onCompleted: {
      lifetime.start(Number(item?.popupTime || Date.now()), Number(item?.pausedMs || 0));
      showAnim.start();
    }

    Connections {
      target: toast.notification
      function onExpireTimeoutChanged() {
        lifetime.restart(true);
      }
      function onAppNameChanged() {
        lifetime.restart(true);
      }
      function onAppIconChanged() {
        lifetime.restart(true);
      }
      function onSummaryChanged() {
        lifetime.restart(true);
      }
      function onBodyChanged() {
        lifetime.restart(true);
      }
      function onActionsChanged() {
        lifetime.restart(true);
      }
      function onImageChanged() {
        lifetime.restart(true);
      }
      function onHasInlineReplyChanged() {
        lifetime.restart(true);
      }
      function onHintsChanged() {
        lifetime.restart(true);
      }
    }

    Connections {
      target: root
      function onNotificationPopupsCloseRequested() {
        toast.close(false);
      }
    }

    ParallelAnimation {
      id: showAnim
      MotionNumberAnimation {
        target: toast
        property: "opacity"
        from: 0
        to: 1
        role: MotionNumberAnimation.Content
      }
      MotionNumberAnimation {
        target: toast
        property: "x"
        from: 32
        to: 0
        role: MotionNumberAnimation.Content
      }
      MotionNumberAnimation {
        target: toast
        property: "scale"
        from: 0.96
        to: 1
        role: MotionNumberAnimation.Content
      }
    }

    ParallelAnimation {
      id: hideAnim
      MotionNumberAnimation {
        target: toast
        property: "opacity"
        to: 0
        role: MotionNumberAnimation.SurfaceExit
      }
      MotionNumberAnimation {
        target: toast
        property: "x"
        to: 40
        role: MotionNumberAnimation.SurfaceExit
      }
      MotionNumberAnimation {
        target: toast
        property: "scale"
        to: 0.97
        role: MotionNumberAnimation.SurfaceExit
      }
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
            color: theme.textMuted
            font.family: theme.uiFontFamily
            font.pixelSize: 11
            font.bold: true
            elide: Text.ElideRight
          }
          Text {
            Layout.fillWidth: true
            text: toast.notification?.summary || ""
            color: theme.textPrimary
            font.family: theme.uiFontFamily
            font.pixelSize: 14
          }
        }
        IconButton {
          glyph: ""
          onClicked: toast.close(true)
        }
      }

      Text {
        Layout.fillWidth: true
        visible: toast.hasBody
        text: toast.bodyText
        textFormat: Text.StyledText
        linkColor: theme.accent
        color: theme.textSecondary
        font.family: theme.uiFontFamily
        font.pixelSize: 13
        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
        maximumLineCount: 3
        elide: Text.ElideRight
        onLinkActivated: function (link) {
          root.openNotificationLink(link);
        }
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
          delegate: ActionButton {
            required property var modelData
            label: root.actionLabel(modelData.action)
            imageSource: root.notificationActionIconSource(modelData.notification, modelData.action)
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
      accentColor: theme.info
      hoverAccentColor: theme.special
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
    radius: 0
    color: bluetoothHover.containsMouse ? theme.surfaceHover : "transparent"
    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: 1
      color: theme.borderMuted
    }

    RowLayout {
      anchors.fill: parent
      anchors.leftMargin: 10
      anchors.rightMargin: 9
      spacing: 10

      ShellSymbol {
        symbol: root.bluetoothDeviceIcon(bluetoothRow.device)
        tint: bluetoothRow.device.connected ? theme.special : theme.textMuted
        size: 24
        Layout.preferredWidth: 24
        Layout.preferredHeight: 24
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 2

        Text {
          Layout.fillWidth: true
          text: bluetoothRow.device.name
          color: theme.textPrimary
          font.family: theme.uiFontFamily
          font.pixelSize: 13
          font.bold: true
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          text: root.bluetoothDeviceDescription(bluetoothRow.device)
          color: theme.textSecondary
          font.family: theme.uiFontFamily
          font.pixelSize: 11
          elide: Text.ElideRight
        }
      }

      IconButton {
        visible: bluetoothRow.device.paired
        glyph: root.pendingBluetoothForgetAddress === bluetoothRow.device.address ? "" : "󰆴"
        tooltip: root.pendingBluetoothForgetAddress === bluetoothRow.device.address ? "Confirm forgetting " + bluetoothRow.device.name : "Forget " + bluetoothRow.device.name
        enabled: !root.bluetoothBusy
        onClicked: root.requestForgetBluetoothDevice(bluetoothRow.device)
      }

      ActionButton {
        label: root.bluetoothDeviceAction(bluetoothRow.device)
        maximumWidth: 126
        flatAction: true
        active: false
        accent: theme.special
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
    radius: 0
    color: wifiHover.containsMouse ? theme.surfaceHover : "transparent"
    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: 1
      color: theme.borderMuted
    }

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
          accent: wifiRow.network.connected ? theme.info : theme.textMuted
        }
        ColumnLayout {
          Layout.fillWidth: true
          spacing: 2
          Text {
            Layout.fillWidth: true
            text: wifiRow.network.name
            color: theme.textPrimary
            font.family: theme.uiFontFamily
            font.pixelSize: 13
            font.bold: true
            elide: Text.ElideRight
          }
          Text {
            Layout.fillWidth: true
            text: root.wifiNetworkDescription(wifiRow.network)
            color: theme.textSecondary
            font.family: theme.uiFontFamily
            font.pixelSize: 11
            elide: Text.ElideRight
          }
        }
        ActionButton {
          label: wifiRow.expanded && !wifiRow.network.connected && !wifiRow.network.stateChanging ? "Connect" : root.wifiNetworkAction(wifiRow.network)
          maximumWidth: 126
          flatAction: true
          active: false
          enabled: !root.wifiBusy && (!wifiRow.expanded || root.pendingPassword.length > 0)
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
          Accessible.name: "Password for " + wifiRow.network.name
          placeholderText: "Network password"
          placeholderTextColor: theme.textMuted
          echoMode: wifiRow.revealPassword ? TextInput.Normal : TextInput.Password
          text: root.pendingPassword
          onTextEdited: root.pendingPassword = text
          enabled: !root.wifiBusy
          color: theme.textSecondary
          font.family: theme.uiFontFamily
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
          glyph: wifiRow.revealPassword ? "󰈈" : "󰈉"
          tooltip: wifiRow.revealPassword ? "Hide network password" : "Show network password"
          enabled: !root.wifiBusy
          onClicked: wifiRow.revealPassword = !wifiRow.revealPassword
        }
        ActionButton {
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
        if (wifiRow.network.connected && root.connectionTargetSsid === wifiRow.network.name) {
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
    property color accent: theme.accent

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
