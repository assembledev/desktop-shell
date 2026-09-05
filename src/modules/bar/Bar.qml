import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import Quickshell.Wayland
import Quickshell.Widgets
import "../common"
import "../launcher/LauncherSearch.js" as LauncherSearch
import "BarLayout.js" as BarLayout

Scope {
  id: root

  Theme {
    id: theme
  }

  ShellConfig {
    id: shellConfig
  }

  BarSpacing {
    id: barSpacing
    compact: root.compact
    portrait: root.portraitMode
  }

  HyprlandAdapter {
    id: hyprland
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
  }

  property string backend: Quickshell.env("DESKTOP_SHELL_BACKEND")
  property string stateDir: Quickshell.env("CONTROL_CENTER_STATE_DIR")
  property string preferencesDir: Quickshell.env("DESKTOP_SHELL_PREFERENCES_DIR")
  property string networkControlsPath: Quickshell.env("DESKTOP_SHELL_NETWORK_CONTROLS")
  readonly property var surface: barWindow
  property bool compact: Quickshell.env("DESKTOP_SHELL_BAR_COMPACT") === "1"
  property bool showVram: Quickshell.env("DESKTOP_SHELL_BAR_SHOW_VRAM") !== "0"
  property bool workspaceIcons: Quickshell.env("DESKTOP_SHELL_BAR_WORKSPACE_ICONS") !== "0"
  property bool barOpen: true
  readonly property bool portraitMode: Number(barWindow.screen?.width || 0) > 0
    && Number(barWindow.screen?.width || 0) < Number(barWindow.screen?.height || 0)
  readonly property bool portraitNarrow: portraitMode && Number(barWindow.screen?.width || 0) < 700
  readonly property int desktopBarHeight: 37
  readonly property int portraitPrimaryHeight: 48
  readonly property int portraitSecondaryHeight: 40
  readonly property int barHeight: portraitMode
    ? portraitPrimaryHeight + portraitSecondaryHeight
    : desktopBarHeight

  readonly property string clockText: Qt.formatDateTime(clock.date, "ddd, MMM dd HH:mm")
  readonly property string clockTimeText: Qt.formatDateTime(clock.date, "HH:mm")
  readonly property string clockDateText: Qt.formatDateTime(clock.date, "ddd, MMM d")
  property var metrics: ({ ramText: "--", hasVram: false, vramText: "--" })
  property var battery: ({ available: false, capacity: 0, status: "", power: "" })
  property var keyboard: ({ layout: "", index: 0 })
  property var notificationStatus: ({ text: "", class: "normal", tooltip: "Control center" })
  property bool notificationUnread: false
  property bool dnd: false
  property bool powerMenuOpen: false
  property bool batteryPollingEnabled: true
  property bool batterySegmentHovered: false
  property bool batteryPanelHovered: false
  property bool batteryAnalysisPinned: false
  property bool batteryAnalysisOpen: false
  property bool recording: false
  property double recordingStartedAt: 0
  property string recordingElapsed: "00:00"
  property bool trayTriggerHovered: false
  property bool trayShelfHovered: false
  property bool trayShelfPinned: false
  property bool trayShelfOpen: false
  property int trayOpenMenus: 0
  readonly property string activeTitle: currentWorkspaceTitle()
  readonly property var desktopApplications: workspaceIcons
    ? (DesktopEntries.applications.values || [])
    : []
  property int workspaceIconRevision: 0
  property var sink: Pipewire.defaultAudioSink
  // Inspect every source, including non-default and virtual microphones. Sink
  // monitor capture is output recording and must not light the microphone badge.
  readonly property var microphoneLinks: Pipewire.linkGroups.values.filter(link =>
    Boolean(link.source?.audio && !link.source.isStream && !link.source.isSink))
  readonly property var activeMicrophoneLinks: microphoneLinks.filter(link =>
    link.state === PwLinkState.Active)
  readonly property string microphoneTooltip: {
    const names = [];
    for (const link of activeMicrophoneLinks) {
      const node = link.target;
      const name = String(node?.properties?.["application.name"]
        || node?.description || node?.name || "Unknown app");
      if (names.indexOf(name) < 0)
        names.push(name);
    }
    return "Microphone in use\n" + names.join("\n");
  }
  readonly property int textOpticalYOffset: 1
  readonly property int trayIconSize: portraitMode ? 36 : 20
  readonly property int trayIconImageSize: 20
  readonly property int trayExpandedSpacing: portraitMode ? barSpacing.portraitTrayItemGap : barSpacing.trayItemGap
  readonly property int trayCompactSpacing: portraitMode ? barSpacing.portraitTrayTightGap : barSpacing.trayTightGap
  readonly property int trayOverflowButtonWidth: portraitMode ? 40 : 34
  readonly property int desktopCenterClearance: barSpacing.centerClearance
  readonly property int desktopEdgeInset: barSpacing.edgeInset
  readonly property int desktopWorkspaceCompactWidth: 68
  readonly property int desktopWorkspaceExpandedWidth: 280
  readonly property int desktopWorkspaceGap: barSpacing.workspaceGap
  readonly property int portraitTitleReserve: portraitNarrow ? 120 : 170
  readonly property var trayItems: prioritizedTrayItems()
  readonly property int trayItemCount: trayItems.length
  readonly property int desktopWorkspaceCount: shellConfig.workspaces.length
  readonly property real desktopPreferredWorkspaceWidth: workspaceIcons
    ? BarLayout.workspaceRowWidth(
        desktopWorkspaceCount,
        desktopWorkspaceCompactWidth,
        desktopWorkspaceExpandedWidth,
        desktopWorkspaceGap,
        true)
    : 0
  readonly property real desktopMinimumTrayWidth: BarLayout.minimumTrayWidth(
    trayItemCount, trayIconSize, trayOverflowButtonWidth)
  // Read preferred child sizes, never allocated widths: the compact decision
  // must not depend on the geometry it changes.
  readonly property real desktopFullStatusWidth: fullStatusGroupWidth()
    + barSpacing.groupGap + desktopActionGroup.implicitWidth
  readonly property bool desktopCompactNetwork: !portraitMode
    && BarLayout.shouldCompactNetwork(desktopSideAvailableWidth,
      desktopFullStatusWidth, desktopMinimumTrayWidth, barSpacing.groupGap)
  readonly property real desktopMinimumRightWidth: desktopFullStatusWidth
    + (desktopMinimumTrayWidth > 0 ? desktopMinimumTrayWidth + barSpacing.groupGap : 0)
  readonly property real desktopFullClockWidth: Number(fullClockMeasure.implicitWidth || 0)
  readonly property bool desktopCompactClock: !portraitMode && !recording
    && BarLayout.shouldUseCompactClock(
      Number(barWindow.width || 0),
      desktopFullClockWidth,
      desktopPreferredWorkspaceWidth,
      desktopMinimumRightWidth,
      desktopEdgeInset,
      desktopCenterClearance)
  readonly property string desktopClockText: desktopCompactClock ? clockTimeText : clockText
  readonly property real desktopSideAvailableWidth: BarLayout.availableSideWidth(
    Number(barWindow.width || 0),
    Number(clockTarget.width || 0),
    desktopEdgeInset,
    desktopCenterClearance)
  readonly property bool desktopExpandActiveWorkspace: workspaceIcons
    && BarLayout.shouldExpandActiveWorkspace(
      desktopSideAvailableWidth,
      desktopWorkspaceCount,
      desktopWorkspaceCompactWidth,
      desktopWorkspaceExpandedWidth,
      desktopWorkspaceGap)
  readonly property real desktopTrayWidthBudget: Number(barWindow.width || 0) / 2
    - Number(clockTarget.width || 0) / 2
    - desktopCenterClearance
    - desktopEdgeInset
    - Number(rightStatusRow.implicitWidth || 0)
    - barSpacing.groupGap
  readonly property real portraitTrayWidthBudget: Number(barWindow.width || 0)
    - portraitTitleReserve
    - Number(portraitFixedStatusRow.implicitWidth || 0)
    - barSpacing.groupGap
    - barSpacing.portraitEdgeInset * 2
    - barSpacing.itemGap
  readonly property real trayWidthBudget: Math.max(0, portraitMode
    ? portraitTrayWidthBudget
    : (desktopCompactNetwork ? Math.min(desktopTrayWidthBudget, desktopMinimumTrayWidth) : desktopTrayWidthBudget))
  readonly property int trayInlineCount: inlineTrayCountForBudget()
  readonly property var trayInlineItems: trayItems.slice(0, trayInlineCount)
  readonly property var trayOverflowItems: trayItems.slice(trayInlineCount)
  readonly property int trayOverflowCount: trayOverflowItems.length
  readonly property int trayShelfColumns: Math.min(portraitMode ? 5 : 8, Math.max(1, trayOverflowCount))
  readonly property int trayShelfRows: Math.max(1, Math.ceil(trayOverflowCount / trayShelfColumns))
  readonly property int trayShelfSpacing: portraitMode ? 8 : 12
  readonly property int trayShelfWidth: trayShelfColumns * trayIconSize + Math.max(0, trayShelfColumns - 1) * trayShelfSpacing + 20
  readonly property int trayShelfHeight: trayShelfRows * trayIconSize + Math.max(0, trayShelfRows - 1) * trayShelfSpacing + 20
  readonly property real trayShelfRightMargin: portraitMode
    ? barSpacing.portraitEdgeInset + Number(portraitFixedStatusRow.implicitWidth || 0) + barSpacing.groupGap
    : barSpacing.edgeInset + Number(rightStatusRow.implicitWidth || 0) + barSpacing.groupGap

  MotionTransition {
    id: barTransition
    requested: root.barOpen
  }

  MotionTransition {
    id: trayShelfTransition
    requested: root.barOpen && root.trayShelfOpen && root.trayOverflowCount > 0
  }

  MotionTransition {
    id: batteryAnalysisTransition
    requested: root.battery.available && root.batteryAnalysisOpen && root.barOpen
  }

  MotionTransition {
    id: powerMenuTransition
    requested: root.powerMenuOpen
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

  function workspaceLabel(id) {
    return shellConfig.workspaceLabel(id);
  }

  function toplevelWorkspaceId(toplevel) {
    return Number(toplevel?.workspace?.id || toplevel?.lastIpcObject?.workspace?.id || 0);
  }

  function workspaceToplevels(id) {
    return Hyprland.toplevels.values.filter(function(toplevel) {
      return root.toplevelWorkspaceId(toplevel) === id;
    });
  }

  function workspaceOccupied(id) {
    return workspaceToplevels(id).length > 0;
  }

  function workspaceActive(id) {
    return (Hyprland.focusedWorkspace?.id || 1) === id;
  }

  function workspacePrimaryToplevel(id) {
    const windows = workspaceToplevels(id);
    return windows.find(function(toplevel) { return toplevel.activated; }) || windows[0] || null;
  }

  function toplevelFocusHistoryId(toplevel) {
    const value = Number(toplevel?.lastIpcObject?.focusHistoryID);
    return Number.isFinite(value) ? value : 999999;
  }

  function toplevelWindowData(toplevel) {
    const ipc = toplevel?.lastIpcObject || {};
    return {
      hidden: Boolean(ipc.hidden),
      class: String(toplevel?.wayland?.appId || ipc.class || ""),
      initialClass: String(ipc.initialClass || ""),
      title: String(toplevel?.title || ipc.title || ""),
      initialTitle: String(ipc.initialTitle || "")
    };
  }

  function applicationForToplevel(toplevel) {
    const win = toplevelWindowData(toplevel);
    const best = LauncherSearch.applicationForWindow(desktopApplications, win);

    if (best)
      return {
        key: String(best.id || best.name || win.class),
        icon: String(best.icon || "")
      };

    return {
      key: "window:" + String(win.class || win.title),
      icon: ""
    };
  }

  function workspaceApplications(id) {
    const windows = workspaceToplevels(id).slice().sort(function(a, b) {
      if (Boolean(a?.activated) !== Boolean(b?.activated))
        return a?.activated ? -1 : 1;
      return toplevelFocusHistoryId(a) - toplevelFocusHistoryId(b);
    });
    const seen = {};
    const applications = [];

    for (const toplevel of windows) {
      const app = applicationForToplevel(toplevel);
      if (seen[app.key])
        continue;
      seen[app.key] = true;
      applications.push(app);
      if (applications.length >= 3)
        break;
    }

    return applications.reverse();
  }

  function currentWorkspaceTitle() {
    return normalizeWindowTitle(workspacePrimaryToplevel(Hyprland.focusedWorkspace?.id || 0)?.title || "");
  }

  function focusWorkspace(id) {
    hyprland.focusWorkspace(id);
  }

  function prioritizedTrayItems() {
    const attention = [];
    const regular = [];
    const items = SystemTray.items.values;

    for (const item of items) {
      if (item.status === Status.NeedsAttention)
        attention.push(item);
      else
        regular.push(item);
    }

    return attention.concat(regular);
  }

  function fullStatusGroupWidth() {
    let total = 0;
    let count = 0;
    for (const child of desktopStatusGroup.children) {
      if (!child.visible)
        continue;
      const preferred = child === desktopNetworkControls
        ? desktopNetworkControls.fullWidth
        : (child.Layout.preferredWidth >= 0 ? child.Layout.preferredWidth : child.implicitWidth);
      total += Math.ceil(preferred);
      count++;
    }
    return total + Math.max(0, count - 1) * desktopStatusGroup.spacing;
  }

  function inlineTrayCountForBudget() {
    return BarLayout.inlineTrayCount(
      trayItemCount,
      trayWidthBudget,
      trayIconSize,
      trayExpandedSpacing,
      trayCompactSpacing,
      trayOverflowButtonWidth);
  }

  function updateTrayShelfOpen() {
    if (trayOverflowCount <= 0) {
      trayShelfCloseTimer.stop();
      trayTriggerHovered = false;
      trayShelfHovered = false;
      trayShelfPinned = false;
      trayShelfOpen = false;
    } else if (trayTriggerHovered || trayShelfHovered || trayShelfPinned || trayOpenMenus > 0) {
      trayShelfCloseTimer.stop();
      trayShelfOpen = true;
    } else {
      trayShelfCloseTimer.restart();
    }
  }

  function closeUnpinnedTrayShelf() {
    if (trayShelfPinned)
      return;

    trayShelfCloseTimer.stop();
    trayTriggerHovered = false;
    trayShelfHovered = false;
    trayShelfOpen = false;
  }

  function normalizeWindowTitle(title) {
    return String(title || "");
  }

  function batteryIcon() {
    if (battery.status === "Charging" || battery.status === "Full")
      return battery.status === "Full" ? "󰁹" : "󰂄";
    const level = Math.max(0, Math.min(9, Math.floor(Number(battery.capacity || 0) / 10)));
    return ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"][level];
  }

  function batteryColor() {
    if (battery.status === "Charging" || battery.status === "Full")
      return theme.success;
    const capacity = Number(battery.capacity || 0);
    if (capacity <= 15)
      return theme.danger;
    if (capacity <= 30)
      return theme.warning;
    return theme.success;
  }

  function batteryAnalysis() {
    return battery.analysis || {};
  }

  function batteryMetric(name) {
    const analysis = batteryAnalysis();
    const value = analysis[name];
    return value === undefined || value === null || String(value).length === 0 ? "--" : String(value);
  }

  function updateBatteryAnalysisOpen() {
    if (batterySegmentHovered || batteryPanelHovered || batteryAnalysisPinned) {
      batteryCloseTimer.stop();
      batteryAnalysisOpen = true;
    } else {
      batteryCloseTimer.restart();
    }
  }

  onPortraitModeChanged: {
    trayMenuPopup.closeImmediately();
    root.trayTriggerHovered = false;
    root.trayShelfHovered = false;
    root.trayShelfPinned = false;
    root.trayShelfOpen = false;
    root.batterySegmentHovered = false;
    root.batteryPanelHovered = false;
    root.batteryAnalysisPinned = false;
    root.batteryAnalysisOpen = false;
  }

  onPowerMenuOpenChanged: {
    if (powerMenuOpen)
      trayMenuPopup.closeMenu();
  }

  function keyboardLabel() {
    return shellConfig.keyboardLayoutLabel(keyboard.index);
  }

  function updateNotificationStatus() {
    const nextDnd = dndFile.text().trim() === "1";
    const count = Number(countFile.text().trim() || "0");
    dnd = nextDnd;
    notificationUnread = count > 0;

    if (dnd && notificationUnread) {
      notificationStatus = { text: "", class: "dnd-unread", tooltip: "Control center" };
    } else if (dnd) {
      notificationStatus = { text: "", class: "dnd", tooltip: "Control center" };
    } else if (notificationUnread) {
      notificationStatus = { text: "", class: "unread", tooltip: "Control center" };
    } else {
      notificationStatus = { text: "", class: "normal", tooltip: "Control center" };
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
    recordingElapsed = hours > 0
      ? padRecordingUnit(hours) + ":" + padRecordingUnit(minutes) + ":" + padRecordingUnit(seconds)
      : padRecordingUnit(minutes) + ":" + padRecordingUnit(seconds);
  }

  function refreshAll() {
    metricsProc.running = true;
    if (batteryPollingEnabled)
      batteryProc.running = true;
    keyboardProc.running = true;
  }

  function refreshTelemetry() {
    metricsProc.running = true;
    if (batteryPollingEnabled)
      batteryProc.running = true;
  }

  Component.onCompleted: {
    refreshAll();
    updateNotificationStatus();
  }

  IpcHandler {
    target: "desktopBar"
    function reveal() { root.barOpen = true; }
    function conceal() { root.barOpen = false; }
    function toggle() { root.barOpen = !root.barOpen; }
    function powerOpen() { root.powerMenuOpen = true; }
    function powerClose() { root.powerMenuOpen = false; }
    function powerToggle() { root.powerMenuOpen = !root.powerMenuOpen; }
  }

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

  Timer {
    interval: 300000
    running: true
    repeat: true
    onTriggered: keyboardProc.running = true
  }

  Timer {
    id: batteryCloseTimer
    interval: 140
    repeat: false
    onTriggered: {
      if (!root.batterySegmentHovered && !root.batteryPanelHovered && !root.batteryAnalysisPinned)
        root.batteryAnalysisOpen = false;
    }
  }

  Timer {
    id: trayShelfCloseTimer
    interval: 160
    repeat: false
    onTriggered: {
      if (!root.trayTriggerHovered && !root.trayShelfHovered && !root.trayShelfPinned && root.trayOpenMenus <= 0)
        root.trayShelfOpen = false;
    }
  }

  onTrayOverflowCountChanged: updateTrayShelfOpen()

  FileView {
    id: dndFile
    path: preferencesDir + "/dnd"
    preload: true
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.updateNotificationStatus()
    onTextChanged: root.updateNotificationStatus()
    onLoadFailed: function() { setText("0"); }
  }

  FileView {
    id: recordingStateFile
    path: Quickshell.env("DESKTOP_SHELL_RECORDING_STATE")
    preload: true
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.updateRecordingState()
    onTextChanged: root.updateRecordingState()
    onLoadFailed: function() { root.recording = false; }
  }

  FileView {
    id: countFile
    path: stateDir + "/count"
    preload: true
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.updateNotificationStatus()
    onTextChanged: root.updateNotificationStatus()
    onLoadFailed: function() { setText("0"); }
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

  Process {
    id: batteryProc
    command: [backend, "bar", "battery-json"]
    stdout: StdioCollector {
      onStreamFinished: {
        const nextBattery = root.parseJson(text, root.battery);
        root.battery = nextBattery;
        if (!nextBattery.available) {
          root.batteryPollingEnabled = false;
          root.batterySegmentHovered = false;
          root.batteryPanelHovered = false;
          root.batteryAnalysisOpen = false;
        }
      }
    }
  }

  Process {
    id: keyboardProc
    command: [backend, "bar", "keyboard-json"]
    stdout: StdioCollector {
      onStreamFinished: root.keyboard = root.parseJson(text, root.keyboard)
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (root.workspaceIcons && event.name === "openwindow")
        Qt.callLater(function() { root.workspaceIconRevision++; });

      if (event.name === "activelayout")
        keyboardProc.running = true;
      else if (event.name === "custom" && event.data === "desktop-shell:dismiss-shell-popup") {
        root.powerMenuOpen = false;
        trayMenuPopup.closeMenu();
      }
    }
  }

  TrayMenu {
    id: trayMenuPopup
    shellScreen: shellConfig.screen
    barSurface: barWindow
    barVisible: root.barOpen

    onOpened: function(fromShelf) {
      root.powerMenuOpen = false;
      root.batteryAnalysisPinned = false;
      root.batteryAnalysisOpen = false;
      root.trayOpenMenus = fromShelf ? 1 : 0;
      root.updateTrayShelfOpen();
    }

    onClosed: function(fromShelf) {
      if (fromShelf) {
        root.trayOpenMenus = 0;
        if (root.portraitMode)
          root.trayShelfPinned = false;

        // A menu layer can cover the shelf before its hover handler receives
        // a leave event. Do not let that stale hover keep an unpinned shelf
        // open after the menu has gone away.
        if (!root.trayShelfPinned) {
          root.closeUnpinnedTrayShelf();
          return;
        }
      }
      root.updateTrayShelfOpen();
    }
  }

  PanelWindow {
    id: barWindow
    screen: shellConfig.screen
    visible: true
    color: "transparent"
    exclusiveZone: root.barOpen ? root.barHeight : 0
    implicitHeight: root.barHeight
    WlrLayershell.namespace: "quickshell:bar"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
      top: true
      left: true
      right: true
    }

    mask: Region {
      item: barSurface
    }

    Rectangle {
      id: barSurface
      anchors.left: parent.left
      anchors.right: parent.right
      height: root.barHeight
      y: -root.barHeight * (1 - barTransition.progress)
      opacity: barTransition.progress
      color: theme.surfaceBar
      border.color: "transparent"
      border.width: 0
      clip: true

      Item {
        anchors.fill: parent

        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: 1
          color: theme.borderSubtle
        }

        RowLayout {
          visible: !root.portraitMode
          anchors.left: parent.left
          anchors.leftMargin: barSpacing.edgeInset
          anchors.right: clockTarget.left
          anchors.rightMargin: barSpacing.centerClearance
          anchors.verticalCenter: parent.verticalCenter
          spacing: barSpacing.groupGap

          RowLayout {
            spacing: root.workspaceIcons ? barSpacing.workspaceGap : barSpacing.workspaceTextGap

            Repeater {
              model: root.workspaceIcons ? shellConfig.workspaces : []
              delegate: WorkspaceIconButton {
                required property var modelData
                workspaceId: modelData.id
                label: modelData.label
                active: root.workspaceActive(workspaceId)
                occupied: root.workspaceOccupied(workspaceId)
                applications: {
                  root.workspaceIconRevision;
                  return root.workspaceApplications(workspaceId);
                }
                activeTitle: active ? root.activeTitle : ""
                activeColor: theme.info
                textColor: theme.textPrimary
                mutedColor: theme.textMuted
                hoverColor: theme.surfaceAccent
                compactWidth: root.desktopWorkspaceCompactWidth
                expandedWidth: root.desktopWorkspaceExpandedWidth
                expandActive: root.desktopExpandActiveWorkspace
                targetHeight: root.desktopBarHeight
                onClicked: root.focusWorkspace(workspaceId)
              }
            }

            Repeater {
              model: root.workspaceIcons ? [] : shellConfig.workspaces
              delegate: WorkspaceButton {
                required property var modelData
                workspaceId: modelData.id
                label: modelData.label
                active: root.workspaceActive(workspaceId)
                occupied: root.workspaceOccupied(workspaceId)
                onClicked: root.focusWorkspace(workspaceId)
              }
            }
          }

          Text {
            visible: !root.workspaceIcons
            Layout.fillWidth: true
            text: root.activeTitle
            color: text.length > 0 ? theme.textPrimary : "transparent"
            font.family: theme.fontFamily
            font.pixelSize: 16
            font.bold: true
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
            topPadding: root.textOpticalYOffset
          }

        }

        Item {
          id: clockTarget
          visible: !root.portraitMode
          anchors.centerIn: parent
          width: root.recording ? recordingClock.implicitWidth : clockLabel.implicitWidth
          height: root.barHeight

          Text {
            id: clockLabel
            visible: !root.recording
            anchors.centerIn: parent
            anchors.verticalCenterOffset: root.textOpticalYOffset
            text: root.desktopClockText
            color: theme.textPrimary
            font.family: theme.fontFamily
            font.pixelSize: 16
            font.bold: true
          }

          Text {
            id: fullClockMeasure
            visible: false
            text: root.clockText
            font.family: theme.fontFamily
            font.pixelSize: 16
            font.bold: true
          }

          RecordingIndicator {
            id: recordingClock
            visible: root.recording
            anchors.centerIn: parent
            width: implicitWidth
            height: implicitHeight
            elapsed: root.recordingElapsed
            clockTime: root.clockTimeText
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: Quickshell.execDetached([root.backend, "bar", "calendar"])
          }
        }

        RowLayout {
          visible: !root.portraitMode
          anchors.right: parent.right
          anchors.rightMargin: barSpacing.edgeInset
          anchors.verticalCenter: parent.verticalCenter
          spacing: barSpacing.groupGap

          Item {
            visible: root.trayItemCount > 0
            Layout.preferredWidth: visible ? trayInlineRow.implicitWidth : 0
            Layout.preferredHeight: root.barHeight

            RowLayout {
              id: trayInlineRow
              anchors.centerIn: parent
              spacing: root.trayOverflowCount > 0 ? root.trayCompactSpacing : root.trayExpandedSpacing

              Repeater {
                model: root.trayInlineItems
                delegate: TrayIcon {
                  required property SystemTrayItem modelData
                  item: modelData
                }
              }

              TrayOverflowButton {
                visible: root.trayOverflowCount > 0
                items: root.trayOverflowItems
                onHoveredChanged: {
                  root.trayTriggerHovered = hovered;
                  root.updateTrayShelfOpen();
                }
                onClicked: {
                  root.trayShelfPinned = !root.trayShelfPinned;
                  root.updateTrayShelfOpen();
                }
              }
            }
          }

          RowLayout {
            id: rightStatusRow
            spacing: barSpacing.groupGap

            RowLayout {
              id: desktopStatusGroup
              spacing: barSpacing.itemGap

              MicrophoneIndicator {}

              BarSegment {
                visible: Boolean(root.sink?.ready && root.sink?.audio)
                icon: root.sink?.audio?.muted ? "󰖁" : "󰕾"
                label: root.sink?.audio?.muted ? "OFF" : Math.round((root.sink?.audio?.volume || 0) * 100) + "%"
                iconColor: root.sink?.audio?.muted ? theme.iconMuted : theme.info
                clickable: true
                onClicked: {
                  if (root.sink?.audio)
                    root.sink.audio.muted = !root.sink.audio.muted;
                }
              }

              NetworkControls {
                id: desktopNetworkControls
                compactLabels: root.desktopCompactNetwork
                backend: root.backend
                configPath: root.networkControlsPath
                pollingEnabled: !root.portraitMode
                itemPadding: barSpacing.itemPadding
                itemGap: barSpacing.itemGap
                contentGap: barSpacing.contentGap
              }

              BarSegment {
                icon: "󰟜"
                label: String(root.metrics.ramText || "--").split("/")[0]
                iconColor: theme.resource
              }

              BarSegment {
                visible: root.showVram && root.metrics.hasVram
                icon: "󰢮"
                label: String(root.metrics.vramText || "--").split("/")[0]
                iconColor: theme.info
              }

              Loader {
                id: batterySegmentLoader
                active: root.battery.available
                visible: active
                Layout.preferredWidth: active && item ? item.preferredWidth : 0
                Layout.preferredHeight: root.barHeight

                sourceComponent: BarSegment {
                  icon: root.batteryIcon()
                  label: Math.round(root.battery.capacity || 0) + "%"
                  iconColor: root.batteryColor()
                  textColor: Number(root.battery.capacity || 0) <= 15 && root.battery.status !== "Charging" ? theme.danger : (Number(root.battery.capacity || 0) <= 30 && root.battery.status !== "Charging" ? theme.warning : theme.textPrimary)
                  onHoveredChanged: {
                    root.batterySegmentHovered = hovered;
                    root.updateBatteryAnalysisOpen();
                  }
                }
              }
            }

            RowLayout {
              id: desktopActionGroup
              spacing: barSpacing.itemGap

              BarSegment {
                icon: ""
                label: root.keyboardLabel()
                iconColor: theme.utility
              }

              NotificationSegment {
                icon: root.notificationStatus.text || ""
                unread: root.notificationUnread
                dnd: root.dnd
                onClicked: Quickshell.execDetached([root.backend, "toggle"])
              }

              Text {
                id: powerIcon
                Layout.preferredWidth: barSpacing.actionSize
                Layout.preferredHeight: root.barHeight
                text: ""
                color: powerMouse.containsMouse || root.powerMenuOpen ? theme.dangerStrong : theme.danger
                font.family: theme.fontFamily
                font.pixelSize: 21
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                topPadding: root.textOpticalYOffset
                scale: powerMouse.pressed ? 0.86 : (powerMouse.containsMouse ? 1.08 : 1)

                Behavior on color {
                  MotionColorAnimation { role: MotionNumberAnimation.Feedback }
                }
                Behavior on scale {
                  MotionNumberAnimation { role: MotionNumberAnimation.Feedback }
                }

                MouseArea {
                  id: powerMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.powerMenuOpen = !root.powerMenuOpen
                }
              }
            }
          }
        }

        Item {
          id: portraitBarLayout
          visible: root.portraitMode
          anchors.fill: parent

          Rectangle {
            anchors.left: parent.left
            anchors.leftMargin: barSpacing.portraitEdgeInset
            anchors.right: parent.right
            anchors.rightMargin: barSpacing.portraitEdgeInset
            y: root.portraitPrimaryHeight
            height: 1
            color: Qt.alpha(theme.borderSubtle, 0.68)
          }

          RowLayout {
            id: portraitWorkspaceRow
            anchors.left: parent.left
            anchors.leftMargin: barSpacing.portraitEdgeInset
            anchors.top: parent.top
            height: root.portraitPrimaryHeight
            spacing: root.workspaceIcons ? barSpacing.workspaceGap : barSpacing.workspaceTextGap

            Repeater {
              model: root.workspaceIcons ? shellConfig.workspaces : []
              delegate: WorkspaceIconButton {
                required property var modelData
                workspaceId: modelData.id
                label: modelData.label
                active: root.workspaceActive(workspaceId)
                occupied: root.workspaceOccupied(workspaceId)
                applications: {
                  root.workspaceIconRevision;
                  return root.workspaceApplications(workspaceId);
                }
                activeTitle: ""
                activeColor: theme.info
                textColor: theme.textPrimary
                mutedColor: theme.textMuted
                hoverColor: theme.surfaceAccent
                compactWidth: root.desktopWorkspaceCompactWidth
                expandActive: false
                targetHeight: root.portraitPrimaryHeight
                onClicked: root.focusWorkspace(workspaceId)
              }
            }

            Repeater {
              model: root.workspaceIcons ? [] : shellConfig.workspaces
              delegate: WorkspaceButton {
                required property var modelData
                workspaceId: modelData.id
                label: modelData.label
                active: root.workspaceActive(workspaceId)
                occupied: root.workspaceOccupied(workspaceId)
                targetHeight: root.portraitPrimaryHeight
                onClicked: root.focusWorkspace(workspaceId)
              }
            }
          }

          Item {
            id: portraitClockTarget
            width: root.portraitNarrow ? 92 : 138
            height: root.portraitPrimaryHeight
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter

            Column {
              anchors.centerIn: parent
              spacing: -1

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.clockTimeText
                color: theme.textPrimary
                font.family: theme.fontFamily
                font.pixelSize: 18
                font.bold: true
              }

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: !root.portraitNarrow
                text: root.clockDateText
                color: theme.textMuted
                font.family: theme.fontFamily
                font.pixelSize: 9
                font.bold: true
              }
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: Quickshell.execDetached([root.backend, "bar", "calendar"])
            }
          }

          RowLayout {
            anchors.right: parent.right
            anchors.rightMargin: barSpacing.portraitEdgeInset
            anchors.top: parent.top
            height: root.portraitPrimaryHeight
            spacing: barSpacing.itemGap

            BarSegment {
              visible: !root.portraitNarrow
              icon: ""
              label: root.keyboardLabel()
              iconColor: theme.utility
              targetHeight: root.portraitPrimaryHeight
            }

            NotificationSegment {
              icon: root.notificationStatus.text || ""
              unread: root.notificationUnread
              dnd: root.dnd
              targetHeight: root.portraitPrimaryHeight
              onClicked: Quickshell.execDetached([root.backend, "toggle"])
            }

            Text {
              id: portraitPowerIcon
              Layout.preferredWidth: barSpacing.actionSize
              Layout.preferredHeight: root.portraitPrimaryHeight
              text: ""
              color: portraitPowerMouse.containsMouse || root.powerMenuOpen ? theme.dangerStrong : theme.danger
              font.family: theme.fontFamily
              font.pixelSize: 21
              font.bold: true
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
              topPadding: root.textOpticalYOffset
              scale: portraitPowerMouse.pressed ? 0.86 : (portraitPowerMouse.containsMouse ? 1.08 : 1)

              Behavior on color {
                MotionColorAnimation { role: MotionNumberAnimation.Feedback }
              }
              Behavior on scale {
                MotionNumberAnimation { role: MotionNumberAnimation.Feedback }
              }

              MouseArea {
                id: portraitPowerMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.powerMenuOpen = !root.powerMenuOpen
              }
            }
          }

          RowLayout {
            anchors.left: parent.left
            anchors.leftMargin: barSpacing.portraitEdgeInset
            anchors.right: parent.right
            anchors.rightMargin: barSpacing.portraitEdgeInset
            anchors.top: parent.top
            anchors.topMargin: root.portraitPrimaryHeight + 1
            anchors.bottom: parent.bottom
            spacing: barSpacing.groupGap

            Text {
              Layout.fillWidth: true
              Layout.minimumWidth: root.portraitTitleReserve
              text: root.activeTitle
              color: text.length > 0 ? theme.textPrimary : theme.textMuted
              font.family: theme.fontFamily
              font.pixelSize: 14
              font.bold: true
              elide: Text.ElideRight
              verticalAlignment: Text.AlignVCenter
            }

            RecordingIndicator {
              visible: root.recording
              elapsed: root.recordingElapsed
            }

            Item {
              visible: root.trayItemCount > 0
              Layout.preferredWidth: visible ? portraitTrayInlineRow.implicitWidth : 0
              Layout.preferredHeight: root.portraitSecondaryHeight

              RowLayout {
                id: portraitTrayInlineRow
                anchors.centerIn: parent
                spacing: root.trayOverflowCount > 0 ? root.trayCompactSpacing : root.trayExpandedSpacing

                Repeater {
                  model: root.trayInlineItems
                  delegate: TrayIcon {
                    required property SystemTrayItem modelData
                    item: modelData
                  }
                }

                TrayOverflowButton {
                  visible: root.trayOverflowCount > 0
                  items: root.trayOverflowItems
                  onHoveredChanged: {
                    root.trayTriggerHovered = hovered;
                    root.updateTrayShelfOpen();
                  }
                  onClicked: {
                    root.trayShelfPinned = !root.trayShelfPinned;
                    root.updateTrayShelfOpen();
                  }
                }
              }
            }

            RowLayout {
              id: portraitFixedStatusRow
              spacing: barSpacing.itemGap

              MicrophoneIndicator {}

              BarSegment {
                visible: Boolean(root.sink?.ready && root.sink?.audio)
                icon: root.sink?.audio?.muted ? "󰖁" : "󰕾"
                label: root.sink?.audio?.muted ? "OFF" : Math.round((root.sink?.audio?.volume || 0) * 100) + "%"
                iconColor: root.sink?.audio?.muted ? theme.iconMuted : theme.info
                clickable: true
                targetHeight: root.portraitSecondaryHeight
                onClicked: {
                  if (root.sink?.audio)
                    root.sink.audio.muted = !root.sink.audio.muted;
                }
              }

              NetworkControls {
                backend: root.backend
                configPath: root.networkControlsPath
                pollingEnabled: root.portraitMode
                targetHeight: root.portraitSecondaryHeight
                itemPadding: barSpacing.itemPadding
                itemGap: barSpacing.itemGap
                contentGap: barSpacing.contentGap
              }

              BarSegment {
                visible: root.battery.available
                icon: root.batteryIcon()
                label: Math.round(root.battery.capacity || 0) + "%"
                iconColor: root.batteryColor()
                textColor: Number(root.battery.capacity || 0) <= 15 && root.battery.status !== "Charging"
                  ? theme.danger
                  : (Number(root.battery.capacity || 0) <= 30 && root.battery.status !== "Charging" ? theme.warning : theme.textPrimary)
                clickable: true
                targetHeight: root.portraitSecondaryHeight
                onHoveredChanged: {
                  root.batterySegmentHovered = hovered;
                  root.updateBatteryAnalysisOpen();
                }
                onClicked: {
                  root.batteryAnalysisPinned = !root.batteryAnalysisPinned;
                  root.updateBatteryAnalysisOpen();
                }
              }
            }
          }
        }
      }
    }
  }

  PanelWindow {
    id: trayShelfWindow
    screen: shellConfig.screen
    visible: trayShelfTransition.presented
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "quickshell:trayShelf"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    margins {
      top: root.barHeight
    }

    mask: Region {
      item: root.trayShelfPinned ? trayShelfBox : trayShelfDismissLayer
    }

    Item {
      id: trayShelfDismissLayer
      anchors.fill: parent

      MouseArea {
        anchors.fill: parent
        enabled: !root.trayShelfPinned
        onClicked: root.closeUnpinnedTrayShelf()
      }
    }

    Rectangle {
      id: trayShelfBox
      width: root.trayShelfWidth
      height: root.trayShelfHeight
      anchors.top: parent.top
      anchors.topMargin: 2
      anchors.right: parent.right
      anchors.rightMargin: root.trayShelfRightMargin
      radius: 12
      color: theme.surfaceGlassStrong
      border.color: Qt.alpha(theme.borderSubtle, 0.68)
      border.width: 1
      opacity: trayShelfTransition.progress
      scale: 0.9 + trayShelfTransition.progress * 0.1
      transformOrigin: Item.TopRight
      transform: Translate {
        y: (1 - trayShelfTransition.progress) * -10
      }

      HoverHandler {
        onHoveredChanged: {
          root.trayShelfHovered = hovered;
          root.updateTrayShelfOpen();
        }
      }

      GridLayout {
        anchors.centerIn: parent
        columns: root.trayShelfColumns
        columnSpacing: root.trayShelfSpacing
        rowSpacing: root.trayShelfSpacing

        Repeater {
          model: root.trayOverflowItems
          delegate: TrayIcon {
            required property SystemTrayItem modelData
            item: modelData
            trackShelfMenu: true
          }
        }
      }
    }
  }

  PanelWindow {
    id: batteryAnalysisWindow
    screen: shellConfig.screen
    visible: batteryAnalysisTransition.presented
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: 250
    implicitHeight: batteryAnalysisBox.height + 4
    WlrLayershell.namespace: "quickshell:batteryAnalysis"
    WlrLayershell.layer: WlrLayer.Overlay

    anchors {
      top: true
      right: true
    }

    margins {
      top: root.barHeight
    }

    mask: Region {
      item: batteryAnalysisBox
    }

    Rectangle {
      id: batteryAnalysisBox
      width: 232
      height: batteryAnalysisColumn.implicitHeight + 20
      anchors.top: parent.top
      anchors.topMargin: 2
      anchors.right: parent.right
      anchors.rightMargin: 9
      radius: 12
      color: theme.surfaceGlassStrong
      border.color: Qt.alpha(theme.borderSubtle, 0.68)
      border.width: 1
      opacity: batteryAnalysisTransition.progress
      scale: 0.9 + batteryAnalysisTransition.progress * 0.1
      transformOrigin: Item.TopRight
      transform: Translate {
        y: (1 - batteryAnalysisTransition.progress) * -10
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onContainsMouseChanged: {
          root.batteryPanelHovered = containsMouse;
          root.updateBatteryAnalysisOpen();
        }
      }

      ColumnLayout {
        id: batteryAnalysisColumn
        anchors.fill: parent
        anchors.leftMargin: 11
        anchors.rightMargin: 11
        anchors.topMargin: 10
        anchors.bottomMargin: 10
        spacing: 7

        BatteryMetricRow {
          icon: "󰔟"
          label: "Remaining"
          value: root.batteryMetric("estimateText")
          accent: theme.info
        }

        BatteryMetricRow {
          icon: "󱐋"
          label: "Now"
          value: root.batteryMetric("currentDraw")
          accent: theme.resource
        }

        BatteryMetricRow {
          icon: "󰔚"
          label: "Last hour"
          value: root.batteryMetric("hourAverage")
          accent: theme.utility
        }

        BatteryMetricRow {
          icon: "󰥔"
          label: "Since boot"
          value: root.batteryMetric("bootAverage")
          accent: theme.special
        }
      }
    }
  }

  BarOverlayWindow {
    id: powerMenuWindow
    barSurface: barWindow
    requested: root.powerMenuOpen
    presented: powerMenuTransition.presented
    surfaceNamespace: "quickshell:powerMenu"

    Item {
      id: powerLayer
      anchors.fill: parent

      MouseArea {
        anchors.fill: parent
        enabled: root.powerMenuOpen
        onClicked: root.powerMenuOpen = false
      }

      Rectangle {
        id: powerMenuBox
        width: 226
        height: powerMenuColumn.implicitHeight + 26
        anchors.top: parent.top
        anchors.topMargin: 2
        anchors.right: parent.right
        anchors.rightMargin: 8
        radius: 12
        color: theme.surfaceGlassStrong
        border.color: Qt.alpha(theme.borderSubtle, 0.62)
        border.width: 1
        opacity: powerMenuTransition.progress
        scale: 0.9 + powerMenuTransition.progress * 0.1
        transformOrigin: Item.TopRight
        transform: Translate {
          y: (1 - powerMenuTransition.progress) * -10
        }

        MouseArea {
          anchors.fill: parent
          onClicked: function(mouse) { mouse.accepted = true; }
        }

        ColumnLayout {
          id: powerMenuColumn
          anchors.fill: parent
          anchors.leftMargin: 10
          anchors.rightMargin: 10
          anchors.topMargin: 13
          anchors.bottomMargin: 10
          spacing: 5

          PowerAction {
            icon: ""
            label: "Lock"
            accent: theme.special
            onClicked: {
              root.powerMenuOpen = false;
              Quickshell.execDetached([root.backend, "lock"]);
            }
          }

          PowerAction {
            icon: "󰤄"
            label: "Sleep"
            accent: theme.info
            onClicked: {
              root.powerMenuOpen = false;
              Quickshell.execDetached([root.backend, "bar", "session", "sleep"]);
            }
          }

          PowerAction {
            icon: ""
            label: "Restart"
            accent: theme.warning
            onClicked: {
              root.powerMenuOpen = false;
              Quickshell.execDetached([root.backend, "bar", "session", "restart"]);
            }
          }

          PowerAction {
            icon: ""
            label: "Shutdown"
            accent: theme.danger
            danger: true
            onClicked: {
              root.powerMenuOpen = false;
              Quickshell.execDetached([root.backend, "bar", "session", "shutdown"]);
            }
          }
        }
      }
    }

    Shortcut {
      sequence: "Esc"
      onActivated: root.powerMenuOpen = false
    }
  }

  component WorkspaceButton: Rectangle {
    id: wsButton
    property int workspaceId
    property string label
    property bool active
    property bool occupied
    property int targetHeight: root.barHeight
    readonly property real inactiveOpacity: occupied ? 0.86 : 0.42
    signal clicked

    Layout.preferredWidth: Math.max(30, wsText.implicitWidth + 12)
    Layout.preferredHeight: targetHeight
    color: "transparent"
    radius: 0
    scale: wsPointer.pressed ? 0.94 : (wsPointer.containsMouse ? 1.04 : 1)

    Behavior on scale {
      MotionNumberAnimation { role: MotionNumberAnimation.Feedback }
    }

    Text {
      id: wsText
      anchors.centerIn: parent
      anchors.verticalCenterOffset: root.textOpticalYOffset
      text: wsButton.label
      color: wsButton.active ? theme.info : theme.textPrimary
      opacity: wsButton.active ? 1 : wsButton.inactiveOpacity
      font.family: theme.fontFamily
      font.pixelSize: 16
      font.bold: true

      Behavior on color {
        MotionColorAnimation { role: MotionNumberAnimation.FocusTravel }
      }
      Behavior on opacity {
        MotionNumberAnimation { role: MotionNumberAnimation.Feedback }
      }
    }

    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: parent.top
      anchors.topMargin: 2
      width: wsButton.active ? parent.width - 8 : (wsButton.occupied ? 14 : 0)
      height: wsButton.active ? 3 : 2
      radius: 2
      color: wsText.color
      opacity: wsButton.active ? 1 : wsButton.inactiveOpacity

      Behavior on width {
        MotionNumberAnimation {
          role: MotionNumberAnimation.FocusTravel
          speedMultiplier: 5
        }
      }
    }

    MouseArea {
      id: wsPointer
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: wsButton.clicked()
    }
  }

  component BarSegment: Item {
    id: segment
    property string icon
    property string label
    property color iconColor: theme.textPrimary
    property color textColor: theme.textPrimary
    property bool clickable: false
    readonly property bool hovered: segmentMouse.containsMouse
    property int preferredWidth: content.implicitWidth + barSpacing.itemPadding * 2
    property int targetHeight: root.barHeight
    signal clicked

    Layout.preferredWidth: preferredWidth
    Layout.preferredHeight: targetHeight

    Row {
      id: content
      anchors.centerIn: parent
      spacing: barSpacing.contentGap
      scale: segmentMouse.pressed ? 0.92 : (segment.hovered ? 1.035 : 1)

      Behavior on scale {
        MotionNumberAnimation { role: MotionNumberAnimation.Feedback }
      }

      Text {
        text: segment.icon
        color: segment.iconColor
        font.family: theme.fontFamily
        font.pixelSize: 16
        font.bold: true
        verticalAlignment: Text.AlignVCenter
        y: root.textOpticalYOffset
      }

      Text {
        text: segment.label
        color: segment.textColor
        font.family: theme.fontFamily
        font.pixelSize: 16
        font.bold: true
        verticalAlignment: Text.AlignVCenter
        y: root.textOpticalYOffset
      }
    }

    MouseArea {
      id: segmentMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: segment.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
      acceptedButtons: Qt.LeftButton
      onClicked: {
        if (segment.clickable)
          segment.clicked();
      }
    }
  }

  component MicrophoneIndicator: Rectangle {
    visible: root.activeMicrophoneLinks.length > 0
    implicitWidth: microphoneContent.implicitWidth + barSpacing.itemPadding * 2
    implicitHeight: 24
    Layout.preferredWidth: implicitWidth
    Layout.preferredHeight: implicitHeight
    Layout.alignment: Qt.AlignVCenter
    radius: 8
    color: Qt.alpha(theme.dangerStrong, 0.12)
    border.color: Qt.alpha(theme.dangerStrong, 0.5)
    border.width: 1

    Row {
      id: microphoneContent
      anchors.centerIn: parent
      spacing: barSpacing.contentGap

      Text {
        text: "󰍬"
        color: theme.dangerStrong
        font.family: theme.fontFamily
        font.pixelSize: 16
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        text: "MIC"
        color: theme.dangerStrong
        font.family: theme.fontFamily
        font.pixelSize: 11
        font.bold: true
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    HoverHandler { id: microphoneHover }
    ToolTip.visible: visible && microphoneHover.hovered
    ToolTip.delay: 350
    ToolTip.text: root.microphoneTooltip
  }

  component RecordingIndicator: Rectangle {
    id: indicator
    property string elapsed: "00:00"
    property string clockTime: ""

    implicitWidth: content.implicitWidth + 20
    implicitHeight: 24
    Layout.preferredWidth: implicitWidth
    Layout.preferredHeight: implicitHeight
    radius: 8
    color: Qt.alpha(theme.dangerStrong, 0.12)
    border.color: Qt.alpha(theme.dangerStrong, 0.5)
    border.width: 1

    Row {
      id: content
      anchors.centerIn: parent
      spacing: 7

      Rectangle {
        width: 8
        height: 8
        anchors.verticalCenter: parent.verticalCenter
        radius: 4
        color: theme.dangerStrong

        SequentialAnimation on opacity {
          running: indicator.visible
          loops: Animation.Infinite
          NumberAnimation { from: 1; to: 0.32; duration: 720; easing.type: Easing.InOutSine }
          NumberAnimation { from: 0.32; to: 1; duration: 720; easing.type: Easing.InOutSine }
        }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: root.textOpticalYOffset
        text: "REC"
        color: theme.dangerStrong
        font.family: theme.fontFamily
        font.pixelSize: 12
        font.bold: true
      }

      Rectangle {
        width: 1
        height: 12
        anchors.verticalCenter: parent.verticalCenter
        color: Qt.alpha(theme.dangerStrong, 0.34)
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: root.textOpticalYOffset
        text: indicator.elapsed
        color: theme.textPrimary
        font.family: theme.fontFamily
        font.pixelSize: 12
        font.bold: true
      }

      Rectangle {
        visible: indicator.clockTime.length > 0
        width: visible ? 1 : 0
        height: 12
        anchors.verticalCenter: parent.verticalCenter
        color: Qt.alpha(theme.dangerStrong, 0.34)
      }

      Text {
        visible: indicator.clockTime.length > 0
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: root.textOpticalYOffset
        text: indicator.clockTime
        color: theme.textPrimary
        font.family: theme.fontFamily
        font.pixelSize: 12
        font.bold: true
      }
    }
  }

  component BatteryMetricRow: RowLayout {
    id: metric
    property string icon
    property string label
    property string value
    property color accent: theme.accent

    Layout.fillWidth: true
    Layout.preferredHeight: 23
    spacing: 8

    Rectangle {
      Layout.preferredWidth: 22
      Layout.preferredHeight: 22
      radius: 7
      color: Qt.alpha(metric.accent, 0.14)

      Text {
        anchors.centerIn: parent
        text: metric.icon
        color: metric.accent
        font.family: theme.fontFamily
        font.pixelSize: 12
        font.bold: true
      }
    }

    Text {
      text: metric.label
      color: theme.textPrimary
      font.family: theme.fontFamily
      font.pixelSize: 11
      font.bold: true
      elide: Text.ElideRight
      Layout.fillWidth: true
      verticalAlignment: Text.AlignVCenter
    }

    Item {
      Layout.preferredWidth: 62
      Layout.preferredHeight: 22

      Text {
        anchors.fill: parent
        text: metric.value
        color: theme.textPrimary
        font.family: theme.fontFamily
        font.pixelSize: 12
        font.bold: true
        horizontalAlignment: Text.AlignRight
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
      }
    }
  }

  component NotificationSegment: Item {
    id: notif
    property string icon
    property bool unread
    property bool dnd
    property int targetHeight: root.barHeight
    signal clicked

    Layout.preferredWidth: barSpacing.actionSize
    Layout.preferredHeight: targetHeight

    Text {
      id: notificationIcon
      anchors.centerIn: parent
      anchors.verticalCenterOffset: root.textOpticalYOffset
      text: notif.icon
      color: theme.textPrimary
      font.family: theme.fontFamily
      font.pixelSize: 19
      font.bold: true
      scale: notificationMouse.pressed ? 0.88 : (notificationMouse.containsMouse ? 1.06 : 1)

      Behavior on scale {
        MotionNumberAnimation { role: MotionNumberAnimation.Feedback }
      }
    }

    Rectangle {
      visible: notif.unread
      width: 7
      height: 7
      radius: 4
      color: theme.dangerStrong
      anchors.right: parent.right
      anchors.rightMargin: 4
      anchors.top: parent.top
      anchors.topMargin: 8
    }

    MouseArea {
      id: notificationMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: notif.clicked()
    }
  }

  component TrayIcon: MouseArea {
    id: trayIcon
    required property SystemTrayItem item
    property bool trackShelfMenu: false

    Layout.preferredWidth: root.trayIconSize
    Layout.preferredHeight: root.trayIconSize
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    scale: pressed ? 0.86 : (containsMouse ? 1.08 : 1)

    Behavior on scale {
      MotionNumberAnimation { role: MotionNumberAnimation.Feedback }
    }

    function openMenu() {
      const point = trayIcon.mapToItem(null, trayIcon.width / 2, trayIcon.height);
      const bottom = trayIcon.trackShelfMenu
        ? Math.max(point.y, root.trayShelfHeight + 2)
        : 0;
      trayMenuPopup.openFor(trayIcon.item, point.x, bottom, trayIcon.trackShelfMenu);
    }

    onClicked: function(mouse) {
      if (mouse.button === Qt.LeftButton && item.hasMenu) {
        openMenu();
      } else if (mouse.button === Qt.RightButton && item.hasMenu) {
        openMenu();
      } else if (mouse.button === Qt.LeftButton) {
        item.activate();
        if (trayIcon.trackShelfMenu && root.portraitMode) {
          root.trayShelfPinned = false;
          root.trayShelfOpen = false;
        }
      } else {
        item.secondaryActivate();
        if (trayIcon.trackShelfMenu && root.portraitMode) {
          root.trayShelfPinned = false;
          root.trayShelfOpen = false;
        }
      }
    }

    IconImage {
      width: root.trayIconImageSize
      height: root.trayIconImageSize
      anchors.centerIn: parent
      source: trayIcon.item.icon
    }
  }

  component TrayOverflowButton: Rectangle {
    id: overflow
    property var items: []
    readonly property bool hovered: overflowMouse.containsMouse
    signal clicked

    Layout.preferredWidth: root.trayOverflowButtonWidth
    Layout.preferredHeight: root.portraitMode ? 36 : 24
    radius: root.portraitMode ? 11 : 8
    color: overflow.hovered || root.trayShelfOpen ? theme.surfaceAccent : "transparent"
    border.color: root.trayShelfPinned ? Qt.alpha(theme.accent, 0.72) : "transparent"
    border.width: 1

    scale: overflowMouse.pressed ? 0.9 : (overflow.hovered ? 1.04 : 1)

    Behavior on color {
      MotionColorAnimation { role: MotionNumberAnimation.Feedback }
    }
    Behavior on border.color {
      MotionColorAnimation { role: MotionNumberAnimation.Feedback }
    }
    Behavior on scale {
      MotionNumberAnimation { role: MotionNumberAnimation.Feedback }
    }

    Item {
      anchors.fill: parent

      Repeater {
        model: Math.min(2, overflow.items.length)

        IconImage {
          required property int index
          width: 15
          height: 15
          x: 3 + index * 6
          anchors.verticalCenter: parent.verticalCenter
          source: overflow.items[index]?.icon || ""
          opacity: index === 0 ? 0.68 : 1
        }
      }

      Rectangle {
        width: 17
        height: 17
        radius: 9
        anchors.right: parent.right
        anchors.rightMargin: 1
        anchors.verticalCenter: parent.verticalCenter
        color: theme.surfaceBar
        border.color: Qt.alpha(theme.borderSubtle, 0.72)
        border.width: 1

        Text {
          anchors.centerIn: parent
          anchors.verticalCenterOffset: root.textOpticalYOffset
          text: overflow.items.length > 9 ? "9+" : String(overflow.items.length)
          color: theme.textPrimary
          font.family: theme.fontFamily
          font.pixelSize: overflow.items.length > 9 ? 8 : 9
          font.bold: true
        }
      }
    }

    MouseArea {
      id: overflowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: overflow.clicked()
    }
  }

  component PowerAction: Rectangle {
    id: action
    property string icon
    property string label
    property color accent: theme.accent
    property bool danger: false
    signal clicked

    Layout.fillWidth: true
    Layout.preferredHeight: 42
    radius: 9
    color: powerHover.containsMouse ? (danger ? Qt.alpha(theme.danger, 0.14) : theme.surfaceAccent) : "transparent"
    border.color: "transparent"
    border.width: 0
    scale: powerHover.pressed ? 0.97 : 1

    Behavior on color {
      MotionColorAnimation { role: MotionNumberAnimation.Feedback }
    }
    Behavior on scale {
      MotionNumberAnimation { role: MotionNumberAnimation.Feedback }
    }

    RowLayout {
      anchors.fill: parent
      anchors.leftMargin: 8
      anchors.rightMargin: 8
      spacing: 10

      Rectangle {
        Layout.preferredWidth: 28
        Layout.preferredHeight: 28
        radius: 8
        color: Qt.alpha(action.accent, powerHover.containsMouse ? 0.25 : 0.15)

        Behavior on color {
          MotionColorAnimation { role: MotionNumberAnimation.Feedback }
        }

        Text {
          anchors.centerIn: parent
          text: action.icon
          color: action.accent
          font.family: theme.fontFamily
          font.pixelSize: 14
          font.bold: true
        }
      }

      Text {
        text: action.label
        color: theme.textPrimary
        font.family: theme.fontFamily
        font.pixelSize: 13
        font.bold: true
        Layout.fillWidth: true
        elide: Text.ElideRight
      }

    }

    MouseArea {
      id: powerHover
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: action.clicked()
    }
  }
}
