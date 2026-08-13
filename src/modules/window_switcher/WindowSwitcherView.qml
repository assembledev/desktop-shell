import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import "../common"
import "../common/HyprlandWindow.js" as HyprlandWindow
import "../launcher/LauncherSearch.js" as LauncherSearch

Scope {
  id: root

  Theme {
    id: theme
  }

  ShellConfig { id: shellConfig }
  HyprlandAdapter { id: hyprland }
  MotionTransition {
    id: surfaceTransition
    requested: root.open
  }

  readonly property int configuredScrollingWorkspace: {
    const workspace = Number(Quickshell.env("DESKTOP_SHELL_SCROLLING_WORKSPACE"));
    return Number.isInteger(workspace) && workspace > 0 ? workspace : 0;
  }
  readonly property var workspaces: shellConfig.workspaceIds
  property bool open: false
  property bool sessionActive: false
  property string selectedAddress: ""
  property string originalAddress: ""
  property string draggingAddress: ""
  property int dropWorkspace: 0
  property string dropWindow: ""
  property var windows: []
  property var monitors: []
  property var activeWindow: ({})
  property var focusOrder: []
  property bool nativeRefreshPending: false
  readonly property var desktopApplications: DesktopEntries.applications.values || []

  function addressOf(win) {
    return String(win?.address || "");
  }

  function validWindow(win) {
    const ws = Number(win?.workspace?.id || 0);
    return addressOf(win).length > 0 && workspaces.indexOf(ws) >= 0 && !win?.hidden;
  }

  function orderedWindows() {
    const positions = {};
    for (let index = 0; index < focusOrder.length; index++)
      positions[focusOrder[index]] = index;

    return (windows || []).filter(validWindow).slice().sort(function(a, b) {
      const ai = positions[addressOf(a)];
      const bi = positions[addressOf(b)];
      if (ai !== undefined || bi !== undefined) {
        if (ai === undefined)
          return 1;
        if (bi === undefined)
          return -1;
        if (ai !== bi)
          return ai - bi;
      }
      const ah = Number.isFinite(Number(a.focusHistoryID)) ? Number(a.focusHistoryID) : 999999;
      const bh = Number.isFinite(Number(b.focusHistoryID)) ? Number(b.focusHistoryID) : 999999;
      if (ah !== bh)
        return ah - bh;
      return addressOf(a).localeCompare(addressOf(b));
    });
  }

  function windowByAddress(address) {
    const needle = String(address || "");
    return (windows || []).find(function(win) {
      return addressOf(win) === needle;
    }) || null;
  }

  function windowsForWorkspace(workspace) {
    return (windows || []).filter(function(win) {
      return validWindow(win) && Number(win.workspace?.id || 0) === Number(workspace);
    });
  }

  function isScrollingWorkspace(workspace) {
    return Number(workspace) === configuredScrollingWorkspace;
  }

  function tapeBounds(workspace, monitor) {
    const scale = Math.max(0.1, Number(monitor?.scale || 1));
    const viewportWidth = Math.max(1, Number(monitor?.width || 1920) / scale);
    const monitorX = Number(monitor?.x || 0);
    let minX = 0;
    let maxX = viewportWidth;

    for (const win of windowsForWorkspace(workspace)) {
      const x = Number(win?.at?.[0] || 0) - monitorX;
      minX = Math.min(minX, x);
      maxX = Math.max(maxX, x + Number(win?.size?.[0] || 1));
    }

    return { minX: minX, maxX: maxX, width: Math.max(1, maxX - minX) };
  }

  function columnCount(workspace) {
    const columns = {};
    for (const win of windowsForWorkspace(workspace)) {
      if (!win?.floating)
        columns[String(Number(win?.at?.[0] || 0))] = true;
    }
    return Object.keys(columns).length;
  }

  function toplevelForAddress(address) {
    const needle = String(address || "").replace(/^0x/, "");
    for (const toplevel of ToplevelManager.toplevels.values) {
      if (String(toplevel?.HyprlandToplevel?.address || "") === needle)
        return toplevel;
    }
    return null;
  }

  function activeMonitorData() {
    const current = (monitors || []).find(function(monitor) { return monitor?.focused; });
    if (current)
      return current;
    if ((monitors || []).length > 0)
      return monitors[0];
    return { x: 0, y: 0, width: 1920, height: 1080 };
  }

  function monitorForWindow(win) {
    const monitor = win?.monitor;
    for (const item of monitors || []) {
      if (item?.id === monitor || item?.name === monitor)
        return item;
    }
    return activeMonitorData();
  }

  function applicationForWindow(win) {
    return LauncherSearch.applicationForWindow(desktopApplications, win);
  }

  function iconSource(win) {
    if (!win)
      return "";
    const icon = String(applicationForWindow(win)?.icon || "");
    if (icon.length === 0)
      return Quickshell.iconPath("application-x-executable");
    if (icon.startsWith("/"))
      return "file://" + icon;
    if (icon.indexOf(":") >= 0)
      return icon;
    return Quickshell.iconPath(icon, "application-x-executable");
  }

  function selectedIndex() {
    const candidates = orderedWindows();
    return candidates.findIndex(function(win) {
      return addressOf(win) === selectedAddress;
    });
  }

  function workspaceGridPoint(workspace) {
    return shellConfig.workspacePoint(workspace);
  }

  function windowGridPoint(win) {
    const workspace = Number(win?.workspace?.id || 1);
    const grid = workspaceGridPoint(workspace);
    const monitor = monitorForWindow(win);
    const scale = Math.max(0.1, Number(monitor?.scale || 1));
    const width = Math.max(1, Number(monitor?.width || 1920) / scale);
    const height = Math.max(1, Number(monitor?.height || 1080) / scale);
    const centerX = Number(win?.at?.[0] || 0) - Number(monitor?.x || 0) + Number(win?.size?.[0] || 1) / 2;
    const centerY = Number(win?.at?.[1] || 0) - Number(monitor?.y || 0) + Number(win?.size?.[1] || 1) / 2;
    const bounds = tapeBounds(workspace, monitor);
    const normalizedX = isScrollingWorkspace(workspace)
      ? (centerX - bounds.minX) / bounds.width
      : centerX / width;
    return {
      x: grid.x * 1.25 + Math.max(0, Math.min(1, normalizedX)),
      y: grid.y * 1.35 + Math.max(0, Math.min(1, centerY / height))
    };
  }

  function overviewDirectionalScore(origin, candidate, direction) {
    const dx = candidate.x - origin.x;
    const dy = candidate.y - origin.y;
    let primary = 0;
    let secondary = 0;

    if (direction === "left") {
      if (dx >= -0.001)
        return -1;
      primary = -dx;
      secondary = Math.abs(dy);
    } else if (direction === "right") {
      if (dx <= 0.001)
        return -1;
      primary = dx;
      secondary = Math.abs(dy);
    } else if (direction === "up") {
      if (dy >= -0.001)
        return -1;
      primary = -dy;
      secondary = Math.abs(dx);
    } else {
      if (dy <= 0.001)
        return -1;
      primary = dy;
      secondary = Math.abs(dx);
    }

    return primary + secondary * 0.42;
  }

  function windowRect(win) {
    const x = Number(win?.at?.[0] || 0);
    const y = Number(win?.at?.[1] || 0);
    const width = Math.max(1, Number(win?.size?.[0] || 1));
    const height = Math.max(1, Number(win?.size?.[1] || 1));
    return {
      left: x,
      right: x + width,
      top: y,
      bottom: y + height,
      centerX: x + width / 2,
      centerY: y + height / 2
    };
  }

  function overlapLength(aMin, aMax, bMin, bMax) {
    return Math.max(0, Math.min(aMax, bMax) - Math.max(aMin, bMin));
  }

  function localDirectionalRank(originWin, candidateWin, direction) {
    if (Number(originWin?.workspace?.id || 0) !== Number(candidateWin?.workspace?.id || 0))
      return null;

    const origin = windowRect(originWin);
    const candidate = windowRect(candidateWin);
    let forward = false;
    let gap = 0;
    let overlap = 0;

    if (direction === "left") {
      forward = candidate.centerX < origin.centerX - 0.001;
      gap = Math.max(0, origin.left - candidate.right);
      overlap = overlapLength(origin.top, origin.bottom, candidate.top, candidate.bottom);
    } else if (direction === "right") {
      forward = candidate.centerX > origin.centerX + 0.001;
      gap = Math.max(0, candidate.left - origin.right);
      overlap = overlapLength(origin.top, origin.bottom, candidate.top, candidate.bottom);
    } else if (direction === "up") {
      forward = candidate.centerY < origin.centerY - 0.001;
      gap = Math.max(0, origin.top - candidate.bottom);
      overlap = overlapLength(origin.left, origin.right, candidate.left, candidate.right);
    } else {
      forward = candidate.centerY > origin.centerY + 0.001;
      gap = Math.max(0, candidate.top - origin.bottom);
      overlap = overlapLength(origin.left, origin.right, candidate.left, candidate.right);
    }

    if (!forward || overlap <= 1)
      return null;

    return {
      gap: gap,
      overlap: overlap,
      history: Number.isFinite(Number(candidateWin?.focusHistoryID))
        ? Number(candidateWin.focusHistoryID)
        : 999999
    };
  }

  function rankIsBetter(rank, bestRank) {
    if (!bestRank)
      return true;
    if (Math.abs(rank.gap - bestRank.gap) > 0.001)
      return rank.gap < bestRank.gap;
    if (Math.abs(rank.overlap - bestRank.overlap) > 0.001)
      return rank.overlap > bestRank.overlap;
    return rank.history < bestRank.history;
  }

  function localDirectionalCandidate(current, candidates, direction) {
    let best = null;
    let bestRank = null;
    for (const candidate of candidates) {
      if (addressOf(candidate) === selectedAddress)
        continue;
      const rank = localDirectionalRank(current, candidate, direction);
      if (rank && rankIsBetter(rank, bestRank)) {
        best = candidate;
        bestRank = rank;
      }
    }
    return best;
  }

  function moveSpatialSelection(direction) {
    const current = windowByAddress(selectedAddress);
    const candidates = orderedWindows();
    if (!current || candidates.length === 0)
      return;

    // Hyprland owns focus on a real workspace; this overview additionally owns
    // cross-workspace navigation. Resolve a rectangle-adjacent local window
    // first, then fall back to the overview grid only between workspaces.
    const local = localDirectionalCandidate(current, candidates, direction);
    if (local) {
      selectedAddress = addressOf(local);
      return;
    }

    const currentWorkspace = Number(current?.workspace?.id || 0);
    const origin = windowGridPoint(current);
    let best = null;
    let bestScore = 999999;
    for (const candidate of candidates) {
      if (addressOf(candidate) === selectedAddress)
        continue;
      if (Number(candidate?.workspace?.id || 0) === currentWorkspace)
        continue;
      const score = overviewDirectionalScore(origin, windowGridPoint(candidate), direction);
      if (score >= 0 && score < bestScore) {
        best = candidate;
        bestScore = score;
      }
    }

    if (best)
      selectedAddress = addressOf(best);
  }

  function selectDirection(direction) {
    if (!sessionActive)
      return;

    moveSpatialSelection(direction);
  }

  function windowDataForToplevel(toplevel) {
    return HyprlandWindow.dataForToplevel(toplevel);
  }

  function monitorData(monitor) {
    const ipc = monitor?.lastIpcObject || {};
    return Object.assign({}, ipc, {
      id: Number(monitor?.id ?? ipc.id ?? -1),
      name: String(monitor?.name || ipc.name || ""),
      x: Number(monitor?.x ?? ipc.x ?? 0),
      y: Number(monitor?.y ?? ipc.y ?? 0),
      width: Number(monitor?.width ?? ipc.width ?? 1920),
      height: Number(monitor?.height ?? ipc.height ?? 1080),
      scale: Number(monitor?.scale ?? ipc.scale ?? 1),
      focused: Boolean(monitor?.focused)
    });
  }

  function snapshotState() {
    windows = (Hyprland.toplevels.values || []).map(windowDataForToplevel);
    monitors = (Hyprland.monitors.values || []).map(monitorData);
    const current = Hyprland.activeToplevel
      || (Hyprland.toplevels.values || []).find(function(toplevel) { return toplevel?.activated; });
    activeWindow = current ? windowDataForToplevel(current) : {};
    normalizeFocusOrder();
  }

  function normalizeFocusOrder() {
    const candidates = (windows || []).filter(validWindow);
    const valid = {};
    for (const win of candidates)
      valid[addressOf(win)] = true;

    let order = focusOrder.filter(function(address) { return valid[address]; });
    const fallback = candidates.slice().sort(function(a, b) {
      const ah = Number.isFinite(Number(a.focusHistoryID)) ? Number(a.focusHistoryID) : 999999;
      const bh = Number.isFinite(Number(b.focusHistoryID)) ? Number(b.focusHistoryID) : 999999;
      return ah - bh;
    });
    for (const win of fallback) {
      const address = addressOf(win);
      if (order.indexOf(address) < 0)
        order.push(address);
    }

    const activeAddress = addressOf(activeWindow);
    if (activeAddress.length > 0)
      order = [activeAddress].concat(order.filter(function(address) { return address !== activeAddress; }));
    replaceFocusOrder(order);
  }

  function replaceFocusOrder(order) {
    // This is internal MRU state read imperatively by selection. Mutating it
    // in place avoids invalidating the hidden overview on every focus event.
    focusOrder.splice(0, focusOrder.length);
    for (const address of order)
      focusOrder.push(address);
  }

  function recordFocusedAddress(address) {
    const focused = HyprlandWindow.normalizedAddress(address);
    if (focused.length === 0)
      return;
    replaceFocusOrder([focused].concat(focusOrder.filter(function(item) { return item !== focused; })));
  }

  function finishStateRefresh() {
    if (!nativeRefreshPending)
      return;

    nativeRefreshPending = false;
    stateSettleTimer.stop();
    const selection = selectedAddress;
    snapshotState();
    if (sessionActive && windowByAddress(selection))
      selectedAddress = selection;
  }

  function refreshState() {
    nativeRefreshPending = true;
    if ((Hyprland.toplevels.values || []).length === 0) {
      finishStateRefresh();
      return;
    }
    Hyprland.refreshToplevels();
    stateSettleTimer.restart();
  }

  function advance(action) {
    const candidates = orderedWindows();
    if (candidates.length === 0) {
      open = false;
      return false;
    }

    let index = candidates.findIndex(function(win) {
      return addressOf(win) === selectedAddress;
    });
    if (index < 0)
      index = candidates.findIndex(function(win) {
        return addressOf(win) === addressOf(activeWindow);
      });
    if (index < 0)
      index = 0;

    if (action === "prev")
      index = (index - 1 + candidates.length) % candidates.length;
    else
      index = (index + 1) % candidates.length;
    selectedAddress = addressOf(candidates[index]);
    return true;
  }

  function altTab(action) {
    const requestedAction = action || "next";
    if (!sessionActive) {
      snapshotState();
      originalAddress = addressOf(activeWindow);
      selectedAddress = originalAddress;
      if (!advance(requestedAction))
        return;
      sessionActive = true;
      presentationTimer.restart();
      return;
    }

    advance(requestedAction);
  }

  function commitSelection() {
    const address = selectedAddress;
    presentationTimer.stop();
    sessionActive = false;
    open = false;
    draggingAddress = "";
    dropWorkspace = 0;
    dropWindow = "";
    if (address.length > 0)
      hyprland.focusWindow(address);
  }

  function commit() {
    if (!sessionActive)
      return;
    commitSelection();
  }

  function cancel() {
    presentationTimer.stop();
    sessionActive = false;
    open = false;
    selectedAddress = originalAddress;
    draggingAddress = "";
    dropWorkspace = 0;
    dropWindow = "";
  }

  function moveWindow(address, workspace) {
    if (!address || !workspace)
      return;
    selectedAddress = address;
    hyprland.moveWindowToWorkspace(address, workspace);
    refreshTimer.restart();
  }

  function swapWindow(address, targetAddress) {
    if (!address || !targetAddress || address === targetAddress)
      return;
    selectedAddress = address;
    hyprland.swapWindow(address, targetAddress);
    refreshTimer.restart();
  }

  function finishDrag() {
    const address = draggingAddress;
    const dragged = windowByAddress(address);
    const sourceWorkspace = Number(dragged?.workspace?.id || 0);
    const targetAddress = dropWindow;
    const targetWindow = windowByAddress(targetAddress);
    const targetWorkspace = dropWorkspace > 0
      ? dropWorkspace
      : Number(targetWindow?.workspace?.id || 0);
    draggingAddress = "";

    if (targetWorkspace > 0 && targetWorkspace !== sourceWorkspace)
      moveWindow(address, targetWorkspace);
    else if (targetAddress.length > 0 && targetAddress !== address)
      swapWindow(address, targetAddress);

    dropWorkspace = 0;
    dropWindow = "";
  }

  Timer {
    id: refreshTimer
    interval: 160
    onTriggered: root.refreshState()
  }

  Timer {
    id: presentationTimer
    // A tap switches immediately without ever constructing the overview.
    // Holding Alt presents the visual navigator after the tap/hold boundary.
    interval: 70
    onTriggered: {
      if (!root.sessionActive)
        return;
      root.open = true;
      root.refreshState();
    }
  }

  Timer {
    id: stateSettleTimer
    // Quickshell exposes refreshToplevels() but no completion signal when the
    // returned client objects are unchanged. Allow one frame for the native
    // IPC response; changed objects restart this settle window below.
    interval: 12
    onTriggered: root.finishStateRefresh()
  }

  Instantiator {
    model: Hyprland.toplevels

    Connections {
      required property var modelData
      target: modelData

      function onLastIpcObjectChanged() {
        if (root.nativeRefreshPending)
          stateSettleTimer.restart();
      }
    }
  }

  Connections {
    target: Hyprland

    function onActiveToplevelChanged() {
      root.recordFocusedAddress(Hyprland.activeToplevel?.address || "");
    }
  }

  Component.onCompleted: snapshotState()

  PanelWindow {
    screen: shellConfig.screen
    id: switcherWindow
    visible: surfaceTransition.presented
    color: "transparent"
    exclusiveZone: 0
    WlrLayershell.namespace: "quickshell:windowSwitcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.open
      ? WlrKeyboardFocus.OnDemand
      : WlrKeyboardFocus.None

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    Rectangle {
      id: switcherSurface
      anchors.fill: parent
      color: theme.surfaceScrim
      opacity: surfaceTransition.progress
      focus: true

      onVisibleChanged: {
        if (visible)
          forceActiveFocus();
      }

      Keys.onPressed: event => {
        const keyText = String(event.text || "").toLowerCase();
        const left = event.key === Qt.Key_Left || keyText === "h";
        const right = event.key === Qt.Key_Right || keyText === "l";
        const up = event.key === Qt.Key_Up || keyText === "k";
        const down = event.key === Qt.Key_Down || keyText === "j";

        if (left)
          root.selectDirection("left");
        else if (right)
          root.selectDirection("right");
        else if (up)
          root.selectDirection("up");
        else if (down)
          root.selectDirection("down");
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
          root.commit();
        else if (event.key === Qt.Key_Tab)
          root.advance((event.modifiers & Qt.ShiftModifier) ? "prev" : "next");
        else
          return;

        event.accepted = true;
      }

      Keys.onReleased: event => {
        if (event.key === Qt.Key_Alt) {
          root.commit();
          event.accepted = true;
        }
      }

      MouseArea {
        anchors.fill: parent
        onClicked: root.cancel()
      }

      Rectangle {
        id: overviewPanel
        width: Math.min(parent.width - 64, 1800)
        height: overviewContent.implicitHeight + 28
        anchors.centerIn: parent
        radius: 14
        color: theme.surfaceGlassStrong
        border.color: Qt.alpha(theme.borderSubtle, 0.58)
        border.width: 1
        clip: true
        scale: 0.965 + surfaceTransition.progress * 0.035
        transform: Translate {
          y: (1 - surfaceTransition.progress) * 18
        }

        ColumnLayout {
          id: overviewContent
          anchors.fill: parent
          anchors.margins: 14
          spacing: 10

          Rectangle {
            Layout.fillWidth: true
            implicitHeight: 54
            radius: 0
            color: "transparent"
            border.color: "transparent"
            border.width: 0

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: 2
              anchors.rightMargin: 2
              anchors.bottomMargin: 8
              spacing: 12

              Item {
                Layout.preferredWidth: 32
                Layout.fillHeight: true

                IconImage {
                  width: 26
                  height: 26
                  anchors.centerIn: parent
                  source: root.iconSource(root.windowByAddress(root.selectedAddress))
                  asynchronous: false
                  smooth: true
                  mipmap: true
                }
              }

              ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text {
                  Layout.fillWidth: true
                  text: root.windowByAddress(root.selectedAddress)?.title || "No windows"
                  color: theme.foreground
                  font.family: theme.fontFamily
                  font.pixelSize: 16
                  font.bold: true
                  elide: Text.ElideRight
                }
                Text {
                  Layout.fillWidth: true
                  text: {
                    const win = root.windowByAddress(root.selectedAddress);
                    if (!win)
                      return "";
                    return (win.class || "Window") + " · workspace " + (win.workspace?.id || "");
                  }
                  color: theme.terminalBlue
                  font.family: theme.fontFamily
                  font.pixelSize: 11
                  elide: Text.ElideRight
                }
              }

              ColumnLayout {
                spacing: 2

                Text {
                  Layout.alignment: Qt.AlignRight
                  text: {
                    const index = root.selectedIndex();
                    const count = root.orderedWindows().length;
                    count > 0 ? (index + 1) + " / " + count : "";
                  }
                  color: theme.text
                  font.family: theme.fontFamily
                  font.pixelSize: 12
                }

                Text {
                  Layout.alignment: Qt.AlignRight
                  text: "ARROWS select · RELEASE ALT focus · DRAG move"
                  color: theme.mutedAlt
                  font.family: theme.fontFamily
                  font.pixelSize: 9
                }
              }
            }

            Rectangle {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              height: 1
              color: theme.borderSubtle
              opacity: 0.42
            }
          }

          GridLayout {
            Layout.fillWidth: true
            columns: root.workspaces.length
            uniformCellWidths: true
            columnSpacing: 8
            rowSpacing: 0

            Repeater {
              model: root.workspaces
              delegate: WorkspacePreview {
                required property int modelData
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                workspace: modelData
              }
            }
          }
        }
      }
    }

    Shortcut {
      sequence: "Esc"
      onActivated: root.cancel()
    }
  }

  component WorkspacePreview: Rectangle {
    id: ws
    property int workspace: 1
    readonly property var workspaceWindows: root.windowsForWorkspace(workspace)
    readonly property var previewMonitor: {
      const selected = workspaceWindows.find(function(win) {
        return root.addressOf(win) === root.selectedAddress;
      });
      return root.monitorForWindow(selected || workspaceWindows[0] || null);
    }
    readonly property real monitorScale: Math.max(0.1, Number(previewMonitor?.scale || 1))
    readonly property real monitorWidth: Math.max(1, Number(previewMonitor?.width || 1920) / monitorScale)
    readonly property real monitorHeight: Math.max(1, Number(previewMonitor?.height || 1080) / monitorScale)
    readonly property real monitorAspect: Math.max(1, Math.min(3.6, monitorWidth / monitorHeight))
    readonly property real previewPadding: 10
    readonly property real titleHeight: 34
    readonly property real contentX: previewPadding
    readonly property real contentY: titleHeight
    readonly property real contentWidth: Math.max(1, width - previewPadding * 2)
    readonly property real contentHeight: Math.max(1, contentWidth / monitorAspect)
    readonly property real layoutScale: Math.min(contentWidth / monitorWidth, contentHeight / monitorHeight)
    readonly property bool scrolling: root.isScrollingWorkspace(workspace)
    readonly property var tape: root.tapeBounds(workspace, previewMonitor)
    readonly property real tapeMinX: scrolling ? Number(tape.minX) : 0
    readonly property real tapeWidth: scrolling ? Number(tape.width) : monitorWidth
    readonly property real tapeScale: Math.min(contentWidth / tapeWidth, contentHeight / monitorHeight)
    readonly property real layoutScaleX: scrolling ? tapeScale : layoutScale
    readonly property real layoutScaleY: scrolling ? tapeScale : layoutScale
    readonly property real tapeOffsetY: scrolling
      ? Math.max(0, (contentHeight - monitorHeight * tapeScale) / 2)
      : 0
    readonly property real viewportX: contentX + Math.max(0, -tapeMinX * layoutScaleX)
    readonly property real viewportWidth: Math.min(contentWidth, monitorWidth * layoutScaleX)
    readonly property real viewportY: contentY + tapeOffsetY
    readonly property real viewportHeight: Math.min(contentHeight, monitorHeight * layoutScaleY)
    readonly property bool active: workspaceWindows.some(function(win) {
      return root.addressOf(win) === root.selectedAddress;
    })
    readonly property bool occupied: workspaceWindows.length > 0
    readonly property bool moveTarget: root.dropWorkspace === workspace
    readonly property bool dragSource: workspaceWindows.some(function(win) {
      return root.addressOf(win) === root.draggingAddress;
    })
    Layout.fillWidth: true
    Layout.preferredHeight: titleHeight + contentHeight + previewPadding
    radius: 11
    color: active ? Qt.alpha(theme.blue, 0.08) : Qt.alpha(theme.surfaceGlass, occupied ? 0.72 : 0.38)
    border.color: moveTarget ? theme.purple : active ? Qt.alpha(theme.blue, 0.78) : Qt.alpha(theme.borderSubtle, occupied ? 0.54 : 0.26)
    border.width: 1
    clip: !dragSource
    z: dragSource ? 100 : 0

    Behavior on color {
      enabled: root.open
      MotionColorAnimation { role: MotionNumberAnimation.FocusTravel }
    }
    Behavior on border.color {
      enabled: root.open
      MotionColorAnimation { role: MotionNumberAnimation.FocusTravel }
    }

    DropArea {
      anchors.fill: screenFrame
      onEntered: {
        root.dropWorkspace = ws.workspace;
        root.dropWindow = "";
      }
      onExited: {
        if (root.dropWorkspace === ws.workspace)
          root.dropWorkspace = 0;
      }
    }

    Rectangle {
      id: screenFrame
      x: ws.contentX
      y: ws.contentY
      width: ws.contentWidth
      height: ws.contentHeight
      radius: 8
      color: theme.bgSolid
      border.color: Qt.alpha(theme.borderSubtle, 0.48)
      border.width: 1
      opacity: ws.active ? 0.82 : 0.68
    }

    Text {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.leftMargin: 12
      anchors.topMargin: 9
      text: shellConfig.workspaceLabel(ws.workspace)
      color: ws.active ? theme.blue : theme.foreground
      opacity: ws.occupied || ws.active ? 1 : 0.5
      font.family: theme.fontFamily
      font.pixelSize: 14
      font.bold: true
      z: 40
    }

    Text {
      visible: ws.scrolling
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.rightMargin: 12
      anchors.topMargin: 11
      text: "SCROLL · " + root.columnCount(ws.workspace) + " COLS"
      color: theme.purple
      font.family: theme.fontFamily
      font.pixelSize: 9
      font.bold: true
      z: 40
    }

    Text {
      visible: ws.workspaceWindows.length === 0
      anchors.centerIn: screenFrame
      text: "Empty workspace"
      color: theme.muted
      font.family: theme.fontFamily
      font.pixelSize: 11
      opacity: 0.5
      z: 3
    }

    Repeater {
      model: ws.workspaceWindows
      delegate: SwitcherWindowTile {
        required property var modelData
        workspaceItem: ws
        windowData: modelData
      }
    }

    Rectangle {
      visible: ws.scrolling
      x: ws.viewportX
      y: ws.viewportY
      width: ws.viewportWidth
      height: ws.viewportHeight
      radius: 6
      color: "transparent"
      border.color: Qt.alpha(theme.purple, 0.9)
      border.width: 1
      z: 35

      Text {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: 4
        anchors.topMargin: 2
        text: "VIEW"
        color: theme.purple
        font.family: theme.fontFamily
        font.pixelSize: 7
        font.bold: true
      }
    }

    Rectangle {
      anchors.fill: screenFrame
      radius: screenFrame.radius
      visible: root.draggingAddress.length > 0
      color: ws.moveTarget && !ws.dragSource ? Qt.alpha(theme.purple, 0.2) : Qt.alpha(theme.bgSolid, 0.32)
      border.color: ws.moveTarget && !ws.dragSource ? theme.purple : Qt.alpha(theme.borderSubtle, 0.42)
      border.width: ws.moveTarget && !ws.dragSource ? 2 : 1
      z: 45

      Column {
        anchors.centerIn: parent
        spacing: 4

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: ws.moveTarget && !ws.dragSource ? "󰁔" : shellConfig.workspaceLabel(ws.workspace)
          color: ws.moveTarget && !ws.dragSource ? theme.purple : theme.mutedAlt
          font.family: theme.fontFamily
          font.pixelSize: ws.moveTarget && !ws.dragSource ? 22 : 18
          font.bold: true
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: ws.dragSource ? "CURRENT WORKSPACE"
            : ws.moveTarget ? "RELEASE · MOVE HERE"
            : "WORKSPACE " + ws.workspace
          color: ws.moveTarget && !ws.dragSource ? theme.foreground : theme.mutedAlt
          font.family: theme.fontFamily
          font.pixelSize: 9
          font.bold: ws.moveTarget && !ws.dragSource
        }
      }
    }
  }

  component SwitcherWindowTile: Rectangle {
    id: tile
    property var workspaceItem
    property var windowData
    readonly property string address: root.addressOf(windowData)
    readonly property bool selected: address === root.selectedAddress
    readonly property bool dragging: address === root.draggingAddress
    readonly property var monitor: workspaceItem.previewMonitor
    readonly property real rawSourceX: (windowData?.at?.[0] || 0) - (monitor?.x || 0)
    readonly property real sourceX: workspaceItem.scrolling
      ? rawSourceX - workspaceItem.tapeMinX
      : Math.max(0, rawSourceX)
    readonly property real sourceY: Math.max(0, (windowData?.at?.[1] || 0) - (monitor?.y || 0))
    readonly property real scaleFactorX: workspaceItem.layoutScaleX
    readonly property real scaleFactorY: workspaceItem.layoutScaleY
    readonly property real scaledX: Math.max(0, Math.min(workspaceItem.contentWidth - 1, sourceX * scaleFactorX))
    readonly property real scaledY: Math.max(0, Math.min(workspaceItem.contentHeight - 1, sourceY * scaleFactorY))
    readonly property real availableWidth: Math.max(1, workspaceItem.contentWidth - scaledX)
    readonly property real availableHeight: Math.max(1, workspaceItem.contentHeight - workspaceItem.tapeOffsetY - scaledY)
    property bool suppressClick: false
    property real dragX: 0
    property real dragY: 0
    readonly property string applicationIcon: root.iconSource(windowData)

    x: workspaceItem.contentX + scaledX + dragX
    y: workspaceItem.contentY + workspaceItem.tapeOffsetY + scaledY + dragY
    width: Math.min(availableWidth, Math.max(24, (windowData?.size?.[0] || 480) * scaleFactorX))
    height: Math.min(availableHeight, Math.max(20, (windowData?.size?.[1] || 300) * scaleFactorY))
    radius: Math.min(7, Math.max(4, height * 0.08))
    color: selected ? Qt.alpha(theme.blue, 0.16) : theme.surfaceRaised
    border.color: selected ? theme.blue : (root.dropWindow === address ? theme.purple : Qt.alpha(theme.borderSubtle, 0.78))
    border.width: 1
    z: dragging ? 60 : (selected ? 10 : 2)
    scale: dragging ? 1.04 : (selected ? 1.018 : 1)
    clip: true

    Behavior on scale {
      enabled: root.open || dragging
      MotionNumberAnimation {
        role: tile.dragging
          ? MotionNumberAnimation.Feedback
          : MotionNumberAnimation.FocusTravel
      }
    }
    Behavior on border.color {
      enabled: root.open
      MotionColorAnimation { role: MotionNumberAnimation.FocusTravel }
    }

    Drag.active: dragHandler.active
    Drag.hotSpot.x: width / 2
    Drag.hotSpot.y: height / 2

    DropArea {
      anchors.fill: parent
      enabled: root.draggingAddress.length > 0 && root.draggingAddress !== tile.address
      onEntered: {
        root.dropWindow = tile.address;
        root.dropWorkspace = tile.workspaceItem.workspace;
      }
      onExited: {
        if (root.dropWindow === tile.address)
          root.dropWindow = "";
      }
    }

    Timer {
      id: clickSuppressTimer
      interval: 120
      onTriggered: tile.suppressClick = false
    }

    Loader {
      id: previewLoader
      anchors.fill: parent
      active: root.open && root.toplevelForAddress(tile.address) !== null
      asynchronous: true
      sourceComponent: ScreencopyView {
        captureSource: root.toplevelForAddress(tile.address)
        // Each preview needs a current snapshot, not a continuously captured
        // video stream for every window in the overview.
        live: false
        constraintSize: Qt.size(Math.max(1, width), Math.max(1, height))
      }
    }

    Rectangle {
      visible: !previewLoader.active
      anchors.fill: parent
      color: theme.surfaceSoft

      IconImage {
        anchors.centerIn: parent
        width: Math.min(40, Math.max(22, tile.height * 0.32))
        height: width
        source: tile.applicationIcon
        asynchronous: false
        smooth: true
        mipmap: true
      }
    }

    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: Math.min(28, Math.max(18, parent.height * 0.24))
      color: theme.surfaceGlassStrong

      IconImage {
        id: tileIcon
        visible: parent.width >= 28
        width: Math.min(15, Math.max(11, parent.height - 7))
        height: width
        anchors.left: parent.left
        anchors.leftMargin: 7
        anchors.verticalCenter: parent.verticalCenter
        source: tile.applicationIcon
        asynchronous: false
        smooth: true
        mipmap: true
      }

      Text {
        anchors.fill: parent
        anchors.leftMargin: tileIcon.visible ? 12 + tileIcon.width : 7
        anchors.rightMargin: 7
        verticalAlignment: Text.AlignVCenter
        text: tile.windowData?.title || tile.windowData?.class || "Window"
        color: theme.foreground
        font.family: theme.fontFamily
        font.pixelSize: Math.min(10, Math.max(8, parent.height * 0.42))
        elide: Text.ElideRight
      }
    }

    Rectangle {
      anchors.fill: parent
      radius: tile.radius
      color: "transparent"
      border.color: theme.blue
      border.width: 1
      visible: tile.selected
      opacity: 0.9
      z: 30
    }

    MouseArea {
      anchors.fill: parent
      z: 40
      acceptedButtons: Qt.LeftButton | Qt.MiddleButton
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: function(mouse) {
        if (tile.suppressClick) {
          mouse.accepted = true;
          return;
        }
        if (mouse.button === Qt.MiddleButton) {
          hyprland.closeWindow(tile.address);
          root.refreshTimer.restart();
        } else {
          root.selectedAddress = tile.address;
          root.commit();
        }
      }
    }

    DragHandler {
      id: dragHandler
      target: null
      xAxis.onActiveValueChanged: tile.dragX = dragHandler.xAxis.activeValue
      yAxis.onActiveValueChanged: tile.dragY = dragHandler.yAxis.activeValue
      onActiveChanged: {
        if (active) {
          root.draggingAddress = tile.address;
          root.dropWorkspace = 0;
          root.dropWindow = "";
        } else if (root.draggingAddress === tile.address) {
          tile.suppressClick = true;
          clickSuppressTimer.restart();
          tile.dragX = 0;
          tile.dragY = 0;
          root.finishDrag();
        }
      }
    }
  }
}
