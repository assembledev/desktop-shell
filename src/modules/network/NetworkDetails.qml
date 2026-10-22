pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../common"
import "../control_center"
import "NetworkStatus.js" as Status

Scope {
  id: root

  required property var model
  required property var barSurface
  property bool open: false
  property string feedback: ""
  property string copiedValue: ""
  readonly property var screen: placement.screen
  readonly property alias surface: window
  readonly property bool wifi: model.connected && model.data.type === "wifi"
  signal wifiRequested(var screen)

  Theme { id: theme }
  ShellConfig { id: configuration }
  ScreenPlacement {
    id: placement
    configuration: configuration
    onRemoved: root.closeDetails()
  }
  MotionTransition { id: transition; requested: root.open }
  Binding { target: root.model; property: "detailsActive"; value: root.open }

  function openDetails(screen) {
    if (!placement.capture(screen))
      return;
    feedback = "";
    copiedValue = "";
    window.keyboardRequested = screen === undefined;
    open = true;
  }
  function closeDetails() { open = false; }
  function toggleDetails(screen) {
    if (open && placement.matches(screen))
      closeDetails();
    else
      openDetails(screen);
  }
  function chooseWifi() {
    const target = screen;
    closeDetails();
    wifiRequested(target);
  }
  function copyValue(label, value) {
    if (!value)
      return;
    Quickshell.clipboardText = value;
    copiedValue = value;
    feedback = label + " copied";
    feedbackTimer.restart();
  }
  function connectionSubtitle() {
    if (!model.connected)
      return model.data.available ? "Not connected · Choose Wi-Fi" : "Network service unavailable";
    if (!wifi)
      return "Ethernet connected · Choose Wi-Fi";
    const parts = ["Connected"];
    if (model.signalStrength !== null)
      parts.push(model.signalStrength + "%");
    const band = Status.band(model.data.frequencyMHz);
    if (band)
      parts.push(band);
    if (model.security)
      parts.push(model.security);
    return parts.join(" · ");
  }
  function addressRows() {
    if (!model.connected)
      return [];
    const rows = [];
    for (const address of model.data.ipv4 || [])
      rows.push({ label: "Local IPv4", value: address, copyable: true });
    for (const address of model.data.ipv6 || [])
      rows.push({ label: "IPv6", value: address, copyable: true });
    rows.push({ label: "Gateway", value: model.data.gateway || "", copyable: true });
    if (model.data.gateway6)
      rows.push({ label: "IPv6 gateway", value: model.data.gateway6, copyable: true });
    const dns = model.data.dns || [];
    if (dns.length === 0)
      rows.push({ label: "Link DNS", value: "", copyable: true });
    for (let i = 0; i < dns.length; i++)
      rows.push({ label: i === 0 ? "Link DNS" : "", value: dns[i], copyable: true });
    rows.push({ label: "Interface", value: model.data.interface || "", copyable: false });
    rows.push({ label: "Link rate", value: Status.linkRate(model.data.linkMbps), copyable: false });
    return rows;
  }
  readonly property string pingText: model.ping.state === "reachable" && model.ping.milliseconds !== null
    ? Number(model.ping.milliseconds).toFixed(0) + " ms" : model.ping.state === "timeout" ? "Timed out"
    : model.ping.state === "unavailable" ? "Unavailable" : "…"

  Timer { id: feedbackTimer; interval: 1800; onTriggered: { root.feedback = ""; root.copiedValue = ""; } }
  IpcHandler {
    target: "network"
    function status(): string { return JSON.stringify(root.model.snapshot()); }
    function open(): void { root.openDetails(); }
    function close(): void { root.closeDetails(); }
    function toggle(): void { root.toggleDetails(); }
  }

  BarOverlayWindow {
    id: window
    barSurface: root.barSurface
    targetScreen: root.screen
    requested: root.open
    presented: transition.presented
    surfaceNamespace: "quickshell:network"

    MouseArea {
      anchors.fill: parent
      enabled: root.open
      onClicked: root.closeDetails()
    }
    FocusScope {
      anchors.fill: parent
      focus: root.open
      Shortcut { sequence: "Esc"; enabled: root.open; onActivated: root.closeDetails() }
      Rectangle {
        id: panel
        anchors.top: parent.top
        anchors.topMargin: theme.barPopoverGap
        anchors.right: parent.right
        anchors.rightMargin: 12
        width: Math.min(376, Math.max(1, window.width - 24))
        height: Math.min(content.implicitHeight + 32, Math.max(1, window.height - 16))
        radius: theme.groupRadius
        color: theme.surfaceGlassStrong
        border.color: theme.borderMuted
        border.width: 1
        clip: true
        opacity: transition.progress
        scale: 0.94 + transition.progress * 0.06
        transformOrigin: Item.TopRight
        transform: Translate { y: (1 - transition.progress) * -10 }
        MouseArea { anchors.fill: parent; onClicked: mouse => mouse.accepted = true }
        Flickable {
          anchors.fill: parent
          contentWidth: width
          contentHeight: content.implicitHeight + 32
          boundsBehavior: Flickable.StopAtBounds
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
          ColumnLayout {
            id: content
            x: 16
            y: 16
            width: parent.width - 32
            spacing: 12
            RowLayout {
              Layout.fillWidth: true
              Text {
                Layout.fillWidth: true
                text: root.model.connected && !root.wifi ? "Ethernet" : "Network"
                color: theme.textPrimary
                font.family: theme.uiFontFamily
                font.pixelSize: 16
                font.bold: true
              }
              ShellButton { colors: theme; glyph: "close"; tooltip: "Close network details"; onClicked: root.closeDetails() }
            }
            ShellGroup {
              Layout.fillWidth: true
              implicitHeight: 66
              colors: theme
              ConnectivityRow {
                anchors.fill: parent
                colors: theme
                navigationOnly: true
                active: root.wifi
                glyph: root.wifi ? root.model.icon : "wifi"
                title: root.wifi ? root.model.ssid || "Wi-Fi" : root.model.connected ? "Wi-Fi networks" : "Choose Wi-Fi"
                subtitle: root.connectionSubtitle()
                Accessible.name: "Change Wi-Fi, " + title + ", " + subtitle
                onDetailRequested: root.chooseWifi()
              }
            }
            ColumnLayout {
              Layout.fillWidth: true
              visible: root.model.connected
              spacing: 2
              DetailRow {
                Layout.fillWidth: true
                label: "Ping · 1.1.1.1"
                value: root.pingText
              }
              DetailRow {
                Layout.fillWidth: true
                label: "Public IPv4"
                value: root.model.publicIp.address
                placeholder: root.model.publicIp.state === "unavailable" ? root.model.publicIp.error === "timeout" ? "Lookup timed out" : "Lookup failed" : "…"
                copyable: true
              }
              Repeater {
                model: root.addressRows()
                DetailRow {
                  required property var modelData
                  Layout.fillWidth: true
                  label: modelData.label
                  value: modelData.value
                  copyable: modelData.copyable
                }
              }
              Rectangle { Layout.fillWidth: true; Layout.topMargin: 10; Layout.bottomMargin: 8; implicitHeight: 1; color: theme.borderMuted }
              Text { text: "Current traffic"; color: theme.textMuted; font.family: theme.uiFontFamily; font.pixelSize: 12 }
              RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 8
                spacing: 16
                TrafficValue { glyph: "down"; label: Status.rate(root.model.receiveRate); direction: "received" }
                TrafficValue { glyph: "up"; label: Status.rate(root.model.transmitRate); direction: "sent" }
              }
            }
            Text {
              Layout.fillWidth: true
              visible: !root.model.connected
              text: root.model.data.available ? "No active connection. Choose Wi-Fi or plug in Ethernet." : "NetworkManager is unavailable."
              color: theme.textSecondary
              font.family: theme.uiFontFamily
              font.pixelSize: 13
              wrapMode: Text.Wrap
            }
          }
        }
      }
    }
  }

  component DetailRow: RowLayout {
    id: row
    property string label: ""
    property string value: ""
    property string placeholder: "—"
    property bool copyable: false
    readonly property bool copied: row.value.length > 0 && root.copiedValue === row.value
    implicitHeight: 34
    spacing: 10
    Text {
      Layout.preferredWidth: implicitWidth
      text: row.label
      color: theme.textSecondary
      font.family: theme.uiFontFamily
      font.pixelSize: 13
    }
    Item { Layout.fillWidth: true }
    Text {
      visible: !row.copyable
      text: row.value || row.placeholder
      color: theme.textPrimary
      font.family: theme.uiFontFamily
      font.pixelSize: 13
    }
    Button {
      id: copyButton
      visible: row.copyable
      enabled: row.value.length > 0
      Layout.maximumWidth: Math.max(70, row.width - 110)
      implicitWidth: copyContent.implicitWidth + 12
      implicitHeight: 32
      padding: 6
      hoverEnabled: true
      Accessible.name: "Copy " + (row.label || "DNS address") + ": " + row.value
      onClicked: root.copyValue(row.label || "DNS address", row.value)
      contentItem: RowLayout {
        id: copyContent
        spacing: 8
        Text {
          Layout.fillWidth: true
          text: row.value || row.placeholder
          color: row.copied ? theme.success : theme.textPrimary
          font.family: theme.uiFontFamily
          font.pixelSize: 13
          elide: Text.ElideMiddle
          horizontalAlignment: Text.AlignRight
        }
        ShellSymbol { symbol: row.copied ? "check" : "copy"; tint: row.copied ? theme.success : theme.textMuted; size: 14; visible: copyButton.enabled }
      }
      background: Rectangle {
        radius: theme.controlRadius
        color: copyButton.hovered || copyButton.down ? theme.surfaceHover : "transparent"
        border.width: copyButton.visualFocus ? 2 : 0
        border.color: theme.accent
      }
      ToolTip.visible: hovered
      ToolTip.text: row.copied ? root.feedback : "Copy " + (row.label || "DNS address") + ": " + row.value
    }
  }
  component TrafficValue: RowLayout {
    property string glyph
    property string label
    property string direction
    Layout.fillWidth: true
    spacing: 5
    ShellSymbol { symbol: parent.glyph; tint: theme.info; size: 16 }
    Text { text: parent.label; color: theme.textPrimary; font.family: theme.uiFontFamily; font.pixelSize: 13 }
    Text { text: parent.direction; color: theme.textMuted; font.family: theme.uiFontFamily; font.pixelSize: 11 }
    Item { Layout.fillWidth: true }
  }
}
