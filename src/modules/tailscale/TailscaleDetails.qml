pragma ComponentBehavior: Bound

import QtCore
import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../common"
import "TailscaleStatus.js" as Status

Scope {
  id: root
  required property var model
  required property var networkController
  required property var barSurface
  property bool open: false
  property string page: "peers"
  property string copied: ""
  property string error: ""
  property bool choosingFiles: false
  property bool choosingDestination: false
  property string receivingName: ""
  property var files: []
  property var queue: []
  property int sendIndex: 0
  property int transferEpoch: 0
  property bool uploadInFlight: false
  property string transferState: "idle"
  property string transferPeerId: ""
  property string transferPeerName: ""
  property string transferError: ""
  readonly property bool sending: transferState === "sending"
  readonly property bool dialogOpen: choosingFiles || choosingDestination
  readonly property var screen: placement.screen
  readonly property var selected: model.selected
  readonly property var control: networkController.controls.find(item => item.id === "tailscale") || null
  readonly property var addresses: selected?.addresses || []
  readonly property bool sameTransfer: transferPeerId === model.selectedId
  readonly property bool transferVisible: sameTransfer && transferState !== "idle"
  readonly property alias surface: window

  Theme { id: theme }
  ShellConfig { id: configuration }
  ScreenPlacement { id: placement; configuration: configuration; onRemoved: root.closeDetails() }
  MotionTransition { id: transition; requested: root.open }
  Binding { target: root.model; property: "detailsActive"; value: root.open }
  Timer { id: feedback; interval: 1800; onTriggered: root.copied = "" }

  function openDetails(screen) {
    if (!placement.capture(screen)) return;
    window.keyboardRequested = screen === undefined;
    error = "";
    open = true;
  }
  // A platform chooser owns its request until accepted/rejected. Closing a
  // shell surface must not abandon a portal request or its external window.
  function closeDetails() { open = false; }
  function toggleDetails(screen) {
    if (open && placement.matches(screen)) closeDetails();
    else openDetails(screen);
  }
  function showPeer(id) {
    model.selectedId = id;
    page = "details";
    error = "";
    copied = "";
  }
  function back() {
    page = page === "send" ? "details" : "peers";
    if (page === "peers") model.selectedId = "";
    error = "";
  }
  function copy(value) { Quickshell.clipboardText = value; copied = value; feedback.restart(); }
  function chooseFiles() {
    if (sending || uploadInFlight || !model.canSend) return;
    choosingFiles = true;
    Qt.callLater(() => fileDialog.open());
  }
  function chooseDestination(name) {
    if (save.running) return;
    receivingName = name;
    saveDialog.selectedFile = StandardPaths.writableLocation(StandardPaths.DownloadLocation) + "/" + encodeURIComponent(name);
    choosingDestination = true;
    Qt.callLater(() => saveDialog.open());
  }
  function startSend() {
    if (sending || uploadInFlight || !model.canSend || files.length === 0) return;
    if (transferState === "error" && sameTransfer)
      queue = queue.slice(sendIndex);
    else queue = files.slice();
    transferEpoch++;
    sendIndex = 0;
    transferPeerId = model.selectedId;
    transferPeerName = selected.name;
    transferError = "";
    transferState = "sending";
    sendNext();
  }
  function sendNext() {
    if (!sending) return;
    if (sendIndex >= queue.length) { transferState = "sent"; model.refresh(); return; }
    uploadInFlight = true;
    send.exec([model.backend, "tailscale", "send-file", transferPeerId, queue[sendIndex].path]);
  }
  function cancelSend() {
    transferEpoch++;
    transferState = "cancelled";
    send.running = false;
  }
  function statusText() {
    if (!model.fresh || !model.data.available) return "Tailscale unavailable";
    if (model.connected) return "";
    return ({Stopped:"Disconnected",NeedsLogin:"Sign in required",NeedsMachineAuth:"Approval required",Starting:"Connecting"})[model.data.state] || model.data.state;
  }
  Connections {
    target: root.model
    function onDataChanged() {
      if (root.page === "received" && root.model.data.files.length === 0 && !save.running)
        root.page = "peers";
    }
  }
  IpcHandler {
    target: "tailscale"
    function open(): void { root.openDetails(); }
    function close(): void { root.closeDetails(); }
    function toggle(): void { root.toggleDetails(); }
    function status(): string { return JSON.stringify(Object.assign(root.model.snapshot(), {open:root.open,page:root.page,transferState:root.transferState})); }
    function peer(id: string): bool {
      if (!root.model.data.peers.some(item => item.id === id)) return false;
      root.openDetails(); root.showPeer(id); return true;
    }
  }

  BarOverlayWindow {
    id: window
    barSurface: root.barSurface
    targetScreen: root.screen
    requested: root.open && !root.dialogOpen
    presented: transition.presented && !root.dialogOpen
    surfaceNamespace: "quickshell:tailscale"
    MouseArea { anchors.fill: parent; enabled: root.open; onClicked: root.closeDetails() }
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
        width: Math.min(416, Math.max(1, window.width - 24))
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
            x: 16; y: 16; width: parent.width - 32
            spacing: 12
            RowLayout {
              Layout.fillWidth: true; spacing: 8
              ShellButton { visible: root.page !== "peers"; colors: theme; glyph: "back"; tooltip: "Back"; onClicked: root.back() }
              Text {
                Layout.fillWidth: true
                text: root.page === "peers" ? "Tailscale" : root.page === "received" ? "Received files" : root.page === "send" ? "Send to " + (root.selected?.name || "device") : root.selected?.name || "Device unavailable"
                color: theme.textPrimary; font.family: theme.uiFontFamily; font.pixelSize: 16; font.bold: true; elide: Text.ElideRight
              }
              ShellButton { colors: theme; glyph: "close"; tooltip: "Close Tailscale"; onClicked: root.closeDetails() }
            }
            ColumnLayout {
              visible: root.page === "peers"
              Layout.fillWidth: true; spacing: 12
              ShellGroup {
                colors: theme; Layout.fillWidth: true; implicitHeight: Math.max(66, selfLabel.implicitHeight + 24)
                Item {
                  anchors.fill: parent; anchors.margins: 12
                  Item {
                    id: selfIcon
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    width: 32; height: 32
                    Image {
                      id: selfLogo
                      anchors.fill: parent; anchors.margins: 2
                      source: root.control?.icon || ""
                      sourceSize.width: 64; sourceSize.height: 64
                      fillMode: Image.PreserveAspectFit
                      opacity: root.model.connected ? 1 : 0.5
                    }
                    ShellSymbol {
                      anchors.centerIn: parent
                      visible: selfLogo.source.toString().length === 0 || selfLogo.status === Image.Error
                      symbol: Status.icon(root.model.data.self?.os); size: 24; tint: theme.textSecondary
                    }
                  }
                  Column {
                    id: selfLabel
                    anchors.left: selfIcon.right; anchors.leftMargin: 10
                    anchors.right: selfAddress.left; anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter; spacing: 3
                    Text { width: parent.width; elide: Text.ElideRight; text: root.model.data.self?.name || "This device"; color: theme.textPrimary; font.family: theme.uiFontFamily; font.pixelSize: 14; font.bold: true }
                    Text { width: parent.width; visible: text.length > 0; elide: Text.ElideRight; text: root.statusText(); color: theme.textSecondary; font.family: theme.uiFontFamily; font.pixelSize: 11 }
                    PeerTags { width: parent.width; tags: root.model.data.self?.tags || [] }
                  }
                  CopyButton { id: selfAddress; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; value: root.model.connected ? root.model.data.self?.addresses?.find(address => address.indexOf(":") < 0) || "" : ""; visible: value.length > 0 }
                }
              }
              ColumnLayout {
                visible: root.model.connected
                Layout.fillWidth: true; spacing: 6
                SectionLabel { text: "Online · " + root.model.online.length; visible: root.model.online.length > 0 }
                Repeater { model: root.model.online; PeerRow { required property var modelData; peer: modelData; onClicked: root.showPeer(peer.id) } }
                SectionLabel { text: "Offline · " + root.model.offline.length; visible: root.model.offline.length > 0; Layout.topMargin: root.model.online.length > 0 ? 8 : 0 }
                Repeater { model: root.model.offline; PeerRow { required property var modelData; peer: modelData; onClicked: root.showPeer(peer.id) } }
                Text { visible: root.model.data.peers.length === 0; text: "No devices"; color: theme.textSecondary; font.family: theme.uiFontFamily; font.pixelSize: 13 }
              }
              ShellButton { visible: !root.model.connected && root.model.data.available && root.control !== null; colors: theme; label: "Connect Tailscale"; glyph: "power"; accent: theme.info; onClicked: root.networkController.activate(root.control) }
              ColumnLayout {
                visible: root.model.data.files.length > 0
                Layout.fillWidth: true; spacing: 8
                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: theme.borderMuted }
                Button {
                  id: received
                  Layout.fillWidth: true; implicitHeight: 40; padding: 8; hoverEnabled: true
                  Accessible.name: "Received files, " + root.model.data.files.length
                  onClicked: root.page = "received"
                  contentItem: RowLayout {
                    spacing: 10
                    ShellSymbol { symbol: "down"; tint: theme.info; size: 18; Layout.preferredWidth: 18; Layout.maximumWidth: 18 }
                    Text { text: "Received files"; color: theme.textPrimary; font.family: theme.uiFontFamily; font.pixelSize: 13; Layout.fillWidth: true }
                    Text { text: root.model.data.files.length; color: theme.textSecondary; font.family: theme.uiFontFamily; font.pixelSize: 12 }
                    ShellSymbol { symbol: "right"; tint: theme.textMuted; size: 12; Layout.preferredWidth: 12; Layout.maximumWidth: 12 }
                  }
                  background: Rectangle { radius: theme.controlRadius; color: received.hovered || received.visualFocus ? theme.surfaceHover : "transparent" }
                }
              }
            }
            ColumnLayout {
              visible: root.page === "details"
              Layout.fillWidth: true; spacing: 12
              ShellGroup {
                visible: root.selected !== null
                colors: theme; Layout.fillWidth: true; implicitHeight: Math.max(62, peerSummary.implicitHeight + 24)
                Item {
                  anchors.fill: parent; anchors.margins: 12
                  ShellSymbol { id: peerIcon; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; width: 24; height: 24; symbol: Status.icon(root.selected?.os); size: 24; tint: theme.textPrimary }
                  Column {
                    id: peerSummary
                    anchors.left: peerIcon.right; anchors.leftMargin: 12; anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter; spacing: 4
                    PeerTags { width: parent.width; label: Status.osName(root.selected?.os); labelSize: 14; labelColor: theme.textPrimary; tags: root.selected?.tags || [] }
                    Row {
                      spacing: 6
                      Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 6; height: 6; radius: 3; color: !root.model.fresh ? theme.warning : root.selected?.online ? theme.success : theme.textMuted }
                      Text { text: !root.model.fresh ? "Status unavailable" : root.selected?.expired ? "Key expired" : root.selected?.online ? "Online" : Status.lastSeen(root.selected?.lastSeen, root.model.now); color: theme.textSecondary; font.family: theme.uiFontFamily; font.pixelSize: 11 }
                    }
                  }
                }
              }
              ColumnLayout {
                visible: root.selected !== null
                Layout.fillWidth: true; spacing: 2
                Repeater {
                  model: root.addresses
                  DetailRow { required property string modelData; label: modelData.indexOf(":") >= 0 ? "IPv6" : "IPv4"; value: modelData; copyable: true }
                }
                DetailRow { label: "Hostname"; value: root.selected?.hostname || ""; copyable: true }
                DetailRow { label: "Connection"; value: root.model.connectionText }
                DetailRow { label: "Ping to " + (root.selected?.name || "device"); value: root.model.pingText }
              }
              ShellButton { visible: root.model.canSend && (!root.sending || root.sameTransfer); colors: theme; label: root.sending && root.sameTransfer ? "Sending files…" : "Send files…"; glyph: "up"; accent: theme.info; onClicked: { root.page = "send"; if (root.files.length === 0 && !root.sending) root.chooseFiles(); } }
              Text { visible: root.selected === null; text: "This device is no longer available."; color: theme.textSecondary; font.family: theme.uiFontFamily; font.pixelSize: 13 }
            }
            ColumnLayout {
              visible: root.page === "send"
              Layout.fillWidth: true; spacing: 14
              Text { text: root.files.length + " files · " + Status.bytes(root.files.reduce((total, file) => total + file.size, 0)); color: theme.textSecondary; font.family: theme.uiFontFamily; font.pixelSize: 12 }
              ShellGroup {
                visible: root.files.length > 0
                colors: theme; Layout.fillWidth: true; implicitHeight: fileList.implicitHeight + 24
                ColumnLayout {
                  id: fileList
                  x: 12; y: 12; width: parent.width - 24; spacing: 12
                  Repeater { model: root.files; FileRow { required property var modelData; name: modelData.name; subtitle: Status.bytes(modelData.size) } }
                }
              }
              Text {
                Layout.fillWidth: true; wrapMode: Text.Wrap
                visible: root.transferVisible
                text: root.transferState === "sent" ? "Sent to " + root.transferPeerName : root.transferState === "sending" ? "Sending · " + root.sendIndex + " of " + root.queue.length + " complete" : root.transferState === "cancelled" ? "Cancelled · " + root.sendIndex + " files completed" : root.transferError || "Send failed"
                color: root.transferState === "error" ? theme.danger : root.transferState === "sent" ? theme.success : theme.textPrimary
                font.family: theme.uiFontFamily; font.pixelSize: 13
              }
              ProgressBar { Layout.fillWidth: true; visible: root.sending && root.sameTransfer; indeterminate: true }
              RowLayout {
                Layout.fillWidth: true; spacing: 8
                ShellButton { colors: theme; label: root.files.length > 0 ? "Change files…" : "Choose files…"; flatAction: true; enabled: !root.sending && !root.uploadInFlight && root.model.canSend; onClicked: root.chooseFiles() }
                Item { Layout.fillWidth: true }
                ShellButton { visible: root.sending && root.sameTransfer; colors: theme; label: "Cancel"; onClicked: root.cancelSend() }
                ShellButton { visible: !root.sending && root.transferVisible && root.transferState === "sent"; colors: theme; label: "Done"; onClicked: root.page = "details" }
                ShellButton { visible: !root.sending && root.model.canSend && !(root.transferVisible && root.transferState === "sent"); colors: theme; label: root.transferState === "error" && root.sameTransfer ? "Retry remaining" : "Send"; glyph: "up"; accent: theme.info; enabled: root.files.length > 0 && !root.uploadInFlight; onClicked: root.startSend() }
              }
            }
            ColumnLayout {
              visible: root.page === "received" && root.model.data.files.length > 0
              Layout.fillWidth: true; spacing: 12
              Text { text: "Waiting to be saved"; color: theme.textSecondary; font.family: theme.uiFontFamily; font.pixelSize: 12 }
              ShellGroup {
                colors: theme; Layout.fillWidth: true; implicitHeight: inboxList.implicitHeight + 24
                ColumnLayout {
                  id: inboxList
                  x: 12; y: 12; width: parent.width - 24; spacing: 12
                  Repeater {
                    model: root.model.data.files
                    Item {
                      required property var modelData
                      Layout.fillWidth: true; implicitHeight: 40
                      FileRow { anchors.left: parent.left; anchors.right: saveButton.left; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; name: modelData.name; subtitle: Status.bytes(modelData.size) }
                      ShellButton { id: saveButton; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; colors: theme; label: save.running && root.receivingName === modelData.name ? "Saving…" : "Save…"; enabled: !save.running; flatAction: true; accent: theme.info; onClicked: root.chooseDestination(modelData.name) }
                    }
                  }
                }
              }
            }
            Text { visible: root.error.length > 0; Layout.fillWidth: true; wrapMode: Text.Wrap; text: root.error; color: theme.danger; font.family: theme.uiFontFamily; font.pixelSize: 12 }
          }
        }
      }
    }
    FileDialog {
      id: fileDialog
      title: "Choose files to send"
      fileMode: FileDialog.OpenFiles
      currentFolder: StandardPaths.standardLocations(StandardPaths.HomeLocation)[0]
      onAccepted: {
        root.choosingFiles = false;
        const paths = selectedFiles.map(value => Status.localPath(value));
        if (paths.length === 0 || paths.some(path => !path)) { root.error = "Choose local files."; return; }
        info.exec([root.model.backend, "tailscale", "file-info"].concat(paths));
      }
      onRejected: root.choosingFiles = false
    }
    FileDialog {
      id: saveDialog
      title: "Save received file"
      fileMode: FileDialog.SaveFile
      onAccepted: {
        root.choosingDestination = false;
        const path = Status.localPath(selectedFile);
        if (!path) { root.error = "Choose a local destination."; return; }
        root.error = "";
        save.exec([root.model.backend, "tailscale", "receive", root.receivingName, path]);
      }
      onRejected: root.choosingDestination = false
    }
  }
  Process {
    id: info
    stdout: StdioCollector { id: infoOutput }
    onExited: function(code) {
      try {
        const files = JSON.parse(infoOutput.text);
        if (code !== 0 || !Array.isArray(files) || files.length === 0) throw new Error("Invalid files");
        root.files = files;
        root.transferState = "idle";
        root.error = "";
      } catch (error) { root.error = "Could not read the selected files."; }
    }
  }
  Process {
    id: send
    stderr: StdioCollector { id: sendError }
    onExited: function(code) {
      root.uploadInFlight = false;
      if (!root.sending) return;
      if (code !== 0) { root.transferState = "error"; root.transferError = sendError.text.trim() || "Send failed"; root.model.refresh(); return; }
      root.sendIndex++;
      const epoch = root.transferEpoch;
      Qt.callLater(() => { if (root.transferEpoch === epoch) root.sendNext(); });
    }
  }
  Process {
    id: save
    stdout: StdioCollector { id: saveOutput }
    stderr: StdioCollector { id: saveError }
    onExited: function(code) {
      let result = null;
      try { result = JSON.parse(saveOutput.text); } catch (error) {}
      root.error = code !== 0 || !result?.saved ? saveError.text.trim() || "Could not save the file." : result.inboxRemoved ? "" : "File saved; could not remove the inbox copy.";
      root.model.refresh();
      root.model.refreshInbox();
    }
  }
  component SectionLabel: Text { color: theme.textMuted; font.family: theme.uiFontFamily; font.pixelSize: 11; Layout.fillWidth: true }
  component PeerTags: Flow {
    id: tagList
    required property var tags
    property string label: ""
    property int labelSize: 11
    property color labelColor: theme.textSecondary
    visible: tags.length > 0 || label.length > 0
    spacing: 4
    Text {
      visible: tagList.label.length > 0
      text: tagList.label; textFormat: Text.PlainText; elide: Text.ElideRight
      width: Math.min(implicitWidth, tagList.width); height: tagList.tags.length > 0 ? 20 : implicitHeight
      verticalAlignment: Text.AlignVCenter
      color: tagList.labelColor
      font.family: theme.uiFontFamily; font.pixelSize: tagList.labelSize
    }
    Repeater {
      model: tagList.tags
      Rectangle {
        required property string modelData
        width: Math.min(tagList.width, tagLabel.implicitWidth + 12); height: 20; radius: theme.controlRadius
        color: theme.surfaceRaised; border.width: 1; border.color: theme.borderMuted
        Text {
          id: tagLabel
          anchors.fill: parent; anchors.leftMargin: 6; anchors.rightMargin: 6
          text: modelData; textFormat: Text.PlainText; elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter
          color: theme.textSecondary; font.family: theme.uiFontFamily; font.pixelSize: 10
        }
      }
    }
  }
  component CopyButton: Button {
    id: button
    property string value: ""
    readonly property bool copied: root.copied === value && value.length > 0
    implicitWidth: copyLabel.implicitWidth + 40; implicitHeight: 32; padding: 6
    hoverEnabled: true; enabled: value.length > 0
    Accessible.name: "Copy " + value
    onClicked: root.copy(value)
    contentItem: RowLayout {
      spacing: 8
      Text { id: copyLabel; Layout.fillWidth: true; text: button.value; elide: Text.ElideMiddle; horizontalAlignment: Text.AlignRight; color: button.copied ? theme.success : theme.textPrimary; font.family: theme.uiFontFamily; font.pixelSize: 13 }
      ShellSymbol { symbol: button.copied ? "check" : "copy"; tint: button.copied ? theme.success : theme.textMuted; size: 14; Layout.preferredWidth: 14; Layout.maximumWidth: 14 }
    }
    background: Rectangle { radius: theme.controlRadius; color: button.hovered || button.down ? theme.surfaceHover : "transparent"; border.width: button.visualFocus ? 2 : 0; border.color: theme.accent }
    ToolTip.visible: hovered; ToolTip.text: copied ? "Copied" : "Copy " + value
  }
  component DetailRow: Item {
    id: row
    property string label
    property string value
    property bool copyable: false
    Layout.fillWidth: true; implicitHeight: 34
    Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; width: Math.min(implicitWidth, row.width * 0.42); text: row.label; elide: Text.ElideRight; color: theme.textSecondary; font.family: theme.uiFontFamily; font.pixelSize: 13 }
    CopyButton { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; visible: row.copyable; width: Math.min(implicitWidth, row.width * 0.65); value: row.value }
    Text { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; visible: !row.copyable; text: row.value; color: theme.textPrimary; font.family: theme.uiFontFamily; font.pixelSize: 13 }
  }
  component FileRow: Item {
    id: fileRow
    property string name
    property string subtitle
    Layout.fillWidth: true; implicitHeight: 36
    ShellSymbol { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; symbol: "document"; width: 22; height: 22; size: 22; tint: theme.textSecondary }
    Column {
      anchors.left: parent.left; anchors.leftMargin: 32; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 3
      Text { width: parent.width; elide: Text.ElideRight; text: fileRow.name; color: theme.textPrimary; font.family: theme.uiFontFamily; font.pixelSize: 13 }
      Text { width: parent.width; elide: Text.ElideRight; text: fileRow.subtitle; color: theme.textSecondary; font.family: theme.uiFontFamily; font.pixelSize: 11 }
    }
  }
  component PeerRow: Button {
    id: row
    required property var peer
    Layout.fillWidth: true; implicitHeight: Math.max(52, peerLabel.implicitHeight + 16); padding: 8; hoverEnabled: true
    Accessible.name: peer.name + ", " + (peer.online ? "online" : "offline") + ((peer.tags || []).length > 0 ? ", " + peer.tags.join(", ") : "")
    contentItem: Item {
      ShellSymbol { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; width: 22; height: 22; symbol: Status.icon(row.peer.os); size: 22; tint: row.peer.online ? theme.textPrimary : theme.textSecondary }
      Column {
        id: peerLabel
        anchors.left: parent.left; anchors.leftMargin: 34; anchors.right: status.left; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; spacing: 4
        Text { width: parent.width; elide: Text.ElideRight; text: row.peer.name; color: theme.textPrimary; font.family: theme.uiFontFamily; font.pixelSize: 14; font.bold: true }
        PeerTags { width: parent.width; label: row.peer.expired ? "Key expired" : row.peer.online ? Status.osName(row.peer.os) : Status.lastSeen(row.peer.lastSeen, root.model.now); tags: row.peer.tags || [] }
      }
      Rectangle { id: status; anchors.right: parent.right; anchors.rightMargin: 26; anchors.verticalCenter: parent.verticalCenter; width: 6; height: 6; radius: 3; color: row.peer.online ? theme.success : theme.textMuted }
      ShellSymbol { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: 12; height: 12; symbol: "right"; size: 12; tint: theme.textMuted }
    }
    background: Rectangle { radius: theme.controlRadius; color: row.hovered || row.visualFocus ? theme.surfaceHover : "transparent" }
  }
}
