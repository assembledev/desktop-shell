pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import "../common"
import "LauncherSearch.js" as LauncherSearch

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
    onDismissed: root.commitPendingFocus()
  }

  property string backend: Quickshell.env("DESKTOP_SHELL_BACKEND")
  property bool open: false
  property string mode: "launch"
  property var windows: []
  property var activeWindow: ({})
  property var apps: []
  property var filtered: []
  property var usageHistory: ({})
  property var browserTabState: ({ connected: false, session: "", tabs: [] })
  property int selectedIndex: 0
  property int appReloadAttempts: 0
  property int warmReloadAttempts: 0
  property bool loadingApps: false
  property bool historyLoaded: false
  property var pendingFocusTarget: null

  readonly property int maxResults: 10
  readonly property int maxAppReloadAttempts: 30
  readonly property int maxWarmReloadAttempts: 40
  readonly property bool browserTabsEnabled: Quickshell.env("DESKTOP_SHELL_BROWSER_TABS") === "1"
  readonly property string browserName: Quickshell.env("DESKTOP_SHELL_BROWSER_NAME") || "Browser"
  readonly property string browserEntryId: Quickshell.env("DESKTOP_SHELL_BROWSER_ENTRY_ID") || "firefox"
  readonly property string browserIcon: Quickshell.env("DESKTOP_SHELL_BROWSER_ICON") || "firefox"
  readonly property string browserTabsPath: browserTabsEnabled
    ? Quickshell.env("XDG_RUNTIME_DIR") + "/desktop-shell/browser-tabs.json"
    : ""
  readonly property color bg: theme.surfaceToast
  readonly property color bgRaised: theme.surfaceRaised
  readonly property color bgHover: theme.surfaceHover
  readonly property color text: theme.foreground
  readonly property color muted: theme.mutedAlt
  readonly property color blue: theme.blue
  readonly property color yellow: theme.yellow
  readonly property color green: theme.green
  readonly property color border: theme.border

  function openLauncher() {
    pendingFocusTarget = null;
    surfaceTransition.exitSpeedMultiplier = 1;
    open = true;
    mode = "launch";
    selectedIndex = 0;
    appReloadAttempts = 0;
    loadingApps = true;
    search.text = "";
    reloadApps();
    refreshState();
    refreshHistory();
    Qt.callLater(function() { search.forceActiveFocus(); });
  }

  function openFocusLauncher() {
    openLauncher();
    mode = "focus";
    applyFilter();
  }

  function closeLauncher() {
    open = false;
    appReloadTimer.stop();
  }

  function toggleLauncher() {
    if (open)
      closeLauncher();
    else
      openLauncher();
  }

  function reloadApps() {
    const entries = DesktopEntries.applications.values || [];
    apps = entries.filter(function(app) {
      return app && !app.noDisplay && String(app.name || "").length > 0;
    }).sort(function(a, b) {
      return String(a.name || "").localeCompare(String(b.name || ""));
    });
    loadingApps = open && apps.length === 0 && appReloadAttempts < maxAppReloadAttempts;
    applyFilter();
    if (loadingApps)
      appReloadTimer.restart();
  }

  function retryReloadApps() {
    if (!open || apps.length > 0 || appReloadAttempts >= maxAppReloadAttempts) {
      loadingApps = false;
      return;
    }

    appReloadAttempts++;
    reloadApps();
  }

  function warmReloadApps() {
    if (open || apps.length > 0 || warmReloadAttempts >= maxWarmReloadAttempts) {
      appWarmupTimer.stop();
      return;
    }

    warmReloadAttempts++;
    reloadApps();
  }

  function desktopId(app) {
    return normalize(String(app?.id || "").split("/").pop());
  }

  function refreshState() {
    if (!stateProc.running)
      stateProc.exec([backend, "hypr", "state-json"]);
  }

  function refreshHistory() {
    historyProc.exec([backend, "launcher", "history"]);
  }

  function normalize(value) {
    return LauncherSearch.normalize(value);
  }

  function appMatchScore(query, app) {
    return LauncherSearch.appMatchScore(query, app);
  }

  function windowMatchScore(query, win) {
    return LauncherSearch.windowMatchScore(query, win);
  }

  function tabMatchScore(query, tab) {
    return LauncherSearch.tabMatchScore(query, tab);
  }

  function focusSearchSpec() {
    const raw = normalize(search.text.trim());
    const tabsOnly = raw.startsWith("!");
    return {
      query: tabsOnly ? normalize(raw.slice(1).trim()) : raw,
      tabsOnly: tabsOnly
    };
  }

  function focusTabsOnly() {
    return mode === "focus" && focusSearchSpec().tabsOnly;
  }

  function launchProfileQuery() {
    if (mode !== "launch")
      return null;
    const query = normalize(search.text.trim());
    return query.startsWith("@") ? query.slice(1) : null;
  }

  function emptyResultTitle() {
    if (loadingApps)
      return "Loading applications";
    if (launchProfileQuery() !== null)
      return "No profile found";
    if (mode === "launch")
      return "No application found";
    if (focusTabsOnly()) {
      if (!browserTabState?.connected)
        return "Browser tabs unavailable";
      return focusSearchSpec().query.length > 0
        ? "No matching browser tab"
        : "No browser tab to focus";
    }
    return search.text.length > 0 ? "No matching open target" : "No open window";
  }

  function emptyResultDetail() {
    if (loadingApps)
      return "Desktop entries are still becoming available";
    if (focusTabsOnly() && !browserTabsEnabled)
      return "Browser tab integration is disabled";
    if (focusTabsOnly() && !browserTabState?.connected)
      return browserName + " extension is not connected";
    if (launchProfileQuery() !== null)
      return "Try @ followed by a configured profile ID";
    if (search.text.length > 0)
      return "Try a shorter or different search";
    return mode === "focus"
      ? "Nothing is open to focus yet"
      : "No visible desktop entries are available";
  }

  function windowHistoryId(win) {
    const value = Number(win?.focusHistoryID);
    return Number.isFinite(value) ? value : 999999;
  }

  function isActiveWindow(win) {
    const address = String(win?.address || "");
    return address.length > 0 && address === String(activeWindow?.address || "");
  }

  function workspaceLabel(win) {
    const id = Number(win?.workspace?.id);
    return Number.isFinite(id) ? shellConfig.workspaceLabel(id) : "?";
  }

  function appWindowIdentityScore(app, win) {
    return LauncherSearch.appWindowIdentityScore(app, win);
  }

  function windowsForApp(app, candidates) {
    const source = candidates === undefined ? windows : candidates;
    return (source || []).filter(function(win) {
      return appWindowIdentityScore(app, win) >= 0;
    });
  }

  function currentHyprlandWindows() {
    return (Hyprland.toplevels.values || []).map(function(toplevel) {
      const ipc = toplevel?.lastIpcObject || {};
      return Object.assign({}, ipc, {
        address: String(toplevel?.address || ipc.address || ""),
        class: String(toplevel?.wayland?.appId || ipc.class || ""),
        initialClass: String(ipc.initialClass || ""),
        title: String(toplevel?.title || ipc.title || ""),
        initialTitle: String(ipc.initialTitle || ""),
        hidden: Boolean(ipc.hidden)
      });
    });
  }

  function applicationForEntryId(entryId) {
    const expected = String(entryId || "");
    return (apps || []).find(function(app) {
      return LauncherSearch.desktopEntryFileId(app) === expected;
    }) || null;
  }

  function profileApplications(profileId) {
    const configured = shellConfig.launchProfiles?.[profileId];
    return Array.isArray(configured) ? configured : [];
  }

  function profileSnapshot(profileId) {
    const entryIds = profileApplications(profileId);
    const currentWindows = currentHyprlandWindows();
    let openCount = 0;
    for (const entryId of entryIds) {
      const app = applicationForEntryId(entryId);
      if (!app)
        continue;
      if (windowsForApp(app, currentWindows).length > 0)
        openCount++;
    }
    return {
      open: openCount,
      total: entryIds.length
    };
  }

  function profileSummary(profileId) {
    const snapshot = profileSnapshot(profileId);
    if (snapshot.total === 0)
      return "Empty profile";
    if (snapshot.open === snapshot.total)
      return snapshot.total + "/" + snapshot.total + " open · nothing to launch";
    return snapshot.open + "/" + snapshot.total + " open · launch missing applications";
  }

  function profileResultEntries(query) {
    const result = [];
    for (const profileId of Object.keys(shellConfig.launchProfiles || {}).sort()) {
      let score = 0;
      if (query.length > 0) {
        if (profileId === query)
          score = 9000;
        else if (profileId.startsWith(query))
          score = 8800;
        else if (profileId.includes(query))
          score = 8600;
        else
          continue;
      }

      result.push({
        kind: "profile",
        profileId: profileId,
        score: score,
        usageScore: 0,
        windows: [],
        entry: {
          id: "profile-" + profileId,
          name: "@" + profileId,
          icon: "system-run"
        }
      });
    }
    return result;
  }

  function applyProfile(profileId) {
    const entryIds = profileApplications(profileId);
    if (entryIds.length === 0) {
      console.error("launcher: unknown or empty profile: " + profileId);
      return;
    }

    reloadApps();
    const currentWindows = currentHyprlandWindows();
    for (const entryId of entryIds) {
      const app = applicationForEntryId(entryId);
      if (app && windowsForApp(app, currentWindows).length > 0)
        continue;
      Quickshell.execDetached([
        backend,
        "launcher",
        "launch-unfocused",
        entryId
      ]);
    }
  }

  function orderedWindows(app, query) {
    return windowsForApp(app).sort(function(a, b) {
      if (query.length > 0) {
        const scoreDelta = windowMatchScore(query, b) - windowMatchScore(query, a);
        if (scoreDelta !== 0)
          return scoreDelta;
      }

      if (isActiveWindow(a) !== isActiveWindow(b))
        return isActiveWindow(a) ? 1 : -1;
      return windowHistoryId(a) - windowHistoryId(b);
    });
  }

  function historyRecord(app) {
    return usageHistory?.[LauncherSearch.desktopEntryFileId(app)] || ({});
  }

  function usageScore(app) {
    const record = historyRecord(app);
    const count = Number(record?.launchCount || 0);
    const lastLaunch = Number(record?.lastLaunch || 0);
    if (!Number.isFinite(count) || count <= 0 || !Number.isFinite(lastLaunch) || lastLaunch <= 0)
      return 0;

    const ageSeconds = Math.max(0, Date.now() / 1000 - lastLaunch);
    const recency = 1200 * Math.exp(-ageSeconds / (14 * 86400));
    const frequency = Math.min(800, Math.log(count + 1) / Math.LN2 * 150);
    return recency + frequency;
  }

  function decoratedEntry(app, query) {
    const wins = orderedWindows(app, query);
    const appScore = appMatchScore(query, app);

    return {
      kind: "app",
      entry: app,
      score: appScore,
      appScore: appScore,
      usageScore: usageScore(app),
      windows: wins,
      windowCount: wins.length
    };
  }

  function focusWindowEntries(query) {
    const candidates = ({});

    for (const app of apps) {
      for (const win of windows || []) {
        const identityScore = appWindowIdentityScore(app, win);
        if (identityScore < 0)
          continue;

        const address = String(win?.address || "");
        const key = address.length > 0
          ? address
          : [win?.class, win?.title, win?.workspace?.id].join("\u0000");
        const existing = candidates[key];
        if (!existing || identityScore > existing.identityScore)
          candidates[key] = { entry: app, window: win, identityScore: identityScore };
      }
    }

    for (const win of windows || []) {
      const address = String(win?.address || "");
      const key = address.length > 0
        ? address
        : [win?.class, win?.title, win?.workspace?.id].join("\u0000");
      if (candidates[key])
        continue;

      const windowClass = String(win?.class || win?.initialClass || "").trim();
      candidates[key] = {
        entry: {
          id: "window-" + (windowClass || key),
          name: windowClass || String(win?.title || "Unknown application"),
          icon: "application-x-executable"
        },
        window: win,
        identityScore: -1
      };
    }

    const result = [];
    for (const key of Object.keys(candidates)) {
      const candidate = candidates[key];
      const appScore = appMatchScore(query, candidate.entry);
      const titleScore = windowMatchScore(query, candidate.window);
      const score = Math.max(appScore, titleScore);
      if (query.length > 0 && score < 0)
        continue;

      result.push({
        kind: "window",
        entry: candidate.entry,
        window: candidate.window,
        score: score,
        appScore: appScore,
        titleScore: titleScore,
        current: isActiveWindow(candidate.window),
        focusRecency: windowHistoryId(candidate.window)
      });
    }

    return result;
  }

  function browserEntry() {
    for (const app of apps) {
      if (desktopId(app) === normalize(browserEntryId))
        return app;
    }

    return {
      id: browserEntryId,
      name: browserName,
      icon: browserIcon
    };
  }

  function tabRecency(tab) {
    const value = Number(tab?.lastAccessed);
    return Number.isFinite(value) ? value : 0;
  }

  function focusTabEntries(query, tabsOnly) {
    if (!browserTabsEnabled || !browserTabState?.connected || !browserTabState?.session)
      return [];

    const result = [];
    const entry = browserEntry();
    for (const tab of browserTabState.tabs || []) {
      if (!tabsOnly && (query.length === 0 || tab?.active))
        continue;

      const score = tabMatchScore(query, tab);
      if (query.length > 0 && score < 0)
        continue;

      result.push({
        kind: "tab",
        entry: entry,
        tab: tab,
        browserSession: String(browserTabState.session),
        score: score,
        current: Boolean(tab?.current),
        tabRecency: tabRecency(tab)
      });
    }

    return result;
  }

  function selectedEntryId() {
    const item = currentItem();
    return item ? desktopId(item.entry) : "";
  }

  function selectedWindowAddress() {
    const win = currentFocusWindow();
    return String(win?.address || "");
  }

  function selectedTabKey() {
    const item = currentItem();
    if (item?.kind !== "tab")
      return "";
    return String(item.browserSession) + ":" + String(item.tab?.tabId);
  }

  function selectPreferredResult(id, preferredWindowAddress, preferredTabKey) {
    if (!id && !preferredWindowAddress && !preferredTabKey)
      return false;

    let appFallback = -1;
    for (let i = 0; i < filtered.length; i++) {
      const item = filtered[i];
      if (preferredTabKey
          && item.kind === "tab"
          && String(item.browserSession) + ":" + String(item.tab?.tabId) === preferredTabKey) {
        selectedIndex = i;
        return true;
      }
      if (preferredWindowAddress
          && String(item.window?.address || "") === preferredWindowAddress) {
        selectedIndex = i;
        return true;
      }
      if (appFallback < 0 && id && desktopId(item.entry) === id)
        appFallback = i;
    }

    if (appFallback >= 0) {
      selectedIndex = appFallback;
      return true;
    }

    return false;
  }

  function applyFilter(preferredId, preferredWindowAddress, preferredTabKey) {
    const focusSpec = focusSearchSpec();
    const query = mode === "focus" ? focusSpec.query : normalize(search.text.trim());
    const profileQuery = launchProfileQuery();
    let result = [];

    if (mode === "focus") {
      if (!focusSpec.tabsOnly)
        result = focusWindowEntries(query);
      if (focusSpec.tabsOnly || query.length > 0)
        result = result.concat(focusTabEntries(query, focusSpec.tabsOnly));
    }

    if (mode === "launch" && profileQuery !== null) {
      result = profileResultEntries(profileQuery);
    } else if (mode === "launch") {
      for (const app of apps) {
        const item = decoratedEntry(app, query);
        if (query.length > 0 && item.score < 0)
          continue;
        result.push(item);
      }
    }

    result.sort(function(a, b) {
      if (query.length > 0 && a.score !== b.score)
        return b.score - a.score;

      if (root.mode === "focus") {
        if (a.current !== b.current)
          return a.current ? 1 : -1;
        if (a.kind === "tab" && b.kind === "tab" && a.tabRecency !== b.tabRecency)
          return b.tabRecency - a.tabRecency;
        if (a.kind === "window" && b.kind === "window" && a.focusRecency !== b.focusRecency)
          return a.focusRecency - b.focusRecency;
        if (a.kind !== b.kind)
          return a.kind === "window" ? -1 : 1;
      } else if (a.usageScore !== b.usageScore) {
        return b.usageScore - a.usageScore;
      }

      return String(a.entry.name || "").localeCompare(String(b.entry.name || ""));
    });

    filtered = result.slice(0, maxResults);
    if (selectPreferredResult(preferredId || "", preferredWindowAddress || "", preferredTabKey || ""))
      return;

    selectedIndex = filtered.length > 0 ? 0 : -1;
  }

  function currentItem() {
    if (selectedIndex < 0 || selectedIndex >= filtered.length)
      return null;
    return filtered[selectedIndex];
  }

  function currentFocusWindow() {
    const item = currentItem();
    return item?.window || null;
  }

  function focusWindow(win) {
    const address = String(win?.address || "");
    if (address.length === 0)
      return false;
    pendingFocusTarget = { kind: "window", address: address };
    surfaceTransition.exitSpeedMultiplier = 5;
    closeLauncher();
    return true;
  }

  function focusTab(item) {
    const session = String(item?.browserSession || "");
    const tabId = Number(item?.tab?.tabId);
    const windowId = Number(item?.tab?.windowId);
    if (!session || !Number.isInteger(tabId) || !Number.isInteger(windowId))
      return false;

    pendingFocusTarget = {
      kind: "tab",
      session: session,
      tabId: tabId,
      windowId: windowId
    };
    surfaceTransition.exitSpeedMultiplier = 5;
    closeLauncher();
    return true;
  }

  function commitPendingFocus() {
    const target = pendingFocusTarget;
    pendingFocusTarget = null;
    if (target?.kind === "window") {
      hyprland.focusWindow(String(target.address || ""));
    } else if (target?.kind === "tab") {
      Quickshell.execDetached([
        backend,
        "browser-tabs",
        "activate",
        String(target.session || ""),
        String(target.tabId),
        String(target.windowId)
      ]);
    }
  }

  function launchApp(item) {
    const app = item?.entry;
    if (!app)
      return;
    const entryId = LauncherSearch.desktopEntryFileId(app);
    if (entryId.length === 0)
      return;
    Quickshell.execDetached([
      backend,
      "launcher",
      "launch",
      entryId
    ]);
    closeLauncher();
  }

  function commit(forceLaunch) {
    const item = currentItem();
    if (!item)
      return;

    if (mode === "launch" && item.kind === "profile") {
      applyProfile(String(item.profileId || ""));
      closeLauncher();
      return;
    }

    if (mode === "focus" && item.kind === "tab") {
      if (!forceLaunch)
        focusTab(item);
      return;
    }

    if (!forceLaunch && mode === "focus" && item.window) {
      focusWindow(currentFocusWindow());
      return;
    }

    launchApp(item);
  }

  function toggleMode() {
    const preferredId = selectedEntryId();
    const preferredWindowAddress = selectedWindowAddress();
    const preferredTabKey = selectedTabKey();
    mode = mode === "launch" ? "focus" : "launch";
    applyFilter(preferredId, preferredWindowAddress, preferredTabKey);
  }

  function setMode(nextMode) {
    if (mode === nextMode)
      return;
    const preferredId = selectedEntryId();
    const preferredWindowAddress = selectedWindowAddress();
    const preferredTabKey = selectedTabKey();
    mode = nextMode;
    applyFilter(preferredId, preferredWindowAddress, preferredTabKey);
  }

  function moveSelection(delta) {
    if (filtered.length === 0)
      return;
    selectedIndex = (selectedIndex + delta + filtered.length) % filtered.length;
  }

  function loadBrowserTabs(raw) {
    const preferredId = selectedEntryId();
    const preferredWindowAddress = selectedWindowAddress();
    const preferredTabKey = selectedTabKey();
    try {
      const state = JSON.parse(raw);
      if (state?.version !== 1
          || state?.connected !== true
          || typeof state?.session !== "string"
          || !Array.isArray(state?.tabs))
        throw new Error("invalid browser tab state");
      browserTabState = state;
    } catch (error) {
      browserTabState = ({ connected: false, session: "", tabs: [] });
      console.error("launcher: failed to parse browser tab state: " + error);
    }
    applyFilter(preferredId, preferredWindowAddress, preferredTabKey);
  }

  function clearBrowserTabs() {
    const preferredId = selectedEntryId();
    const preferredWindowAddress = selectedWindowAddress();
    browserTabState = ({ connected: false, session: "", tabs: [] });
    applyFilter(preferredId, preferredWindowAddress);
  }

  FileView {
    id: browserTabsFile
    path: root.browserTabsPath
    preload: true
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.loadBrowserTabs(text())
    onTextChanged: root.loadBrowserTabs(text())
    onLoadFailed: root.clearBrowserTabs()
  }

  Process {
    id: stateProc
    stdout: StdioCollector {
      onStreamFinished: {
        const preferredId = root.selectedEntryId();
        const preferredWindowAddress = root.selectedWindowAddress();
        const preferredTabKey = root.selectedTabKey();
        try {
          const state = JSON.parse(text);
          root.windows = state.clients || [];
          root.activeWindow = state.active || {};
        } catch (error) {
          root.windows = [];
          root.activeWindow = {};
          console.error("launcher: failed to parse Hyprland state: " + error);
        }
        root.applyFilter(preferredId, preferredWindowAddress, preferredTabKey);
      }
    }
  }

  Process {
    id: historyProc
    stdout: StdioCollector {
      onStreamFinished: {
        const preferredId = root.historyLoaded ? root.selectedEntryId() : "";
        const preferredWindowAddress = root.historyLoaded ? root.selectedWindowAddress() : "";
        const preferredTabKey = root.historyLoaded ? root.selectedTabKey() : "";
        try {
          const history = JSON.parse(text);
          root.usageHistory = history && typeof history === "object" ? history : ({});
        } catch (error) {
          root.usageHistory = ({});
          console.error("launcher: failed to parse usage history: " + error);
        }
        root.historyLoaded = true;
        root.applyFilter(preferredId, preferredWindowAddress, preferredTabKey);
      }
    }
  }

  Timer {
    id: appReloadTimer
    interval: 100
    repeat: false
    onTriggered: root.retryReloadApps()
  }

  Timer {
    id: appWarmupTimer
    interval: 250
    repeat: true
    onTriggered: root.warmReloadApps()
  }

  Component.onCompleted: {
    reloadApps();
    refreshHistory();
    appWarmupTimer.start();
  }

  PanelWindow {
    id: window
    screen: shellConfig.screen
    visible: surfaceTransition.presented
    color: "transparent"
    exclusiveZone: 0

    WlrLayershell.namespace: "quickshell:launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.open
      ? WlrKeyboardFocus.Exclusive
      : WlrKeyboardFocus.None

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    Rectangle {
      anchors.fill: parent
      color: theme.surfaceScrim
      opacity: surfaceTransition.progress
    }

    MouseArea {
      anchors.fill: parent
      enabled: root.open
      onClicked: root.closeLauncher()
    }

    Rectangle {
      id: panel

      width: Math.min(840, window.width - 40)
      height: Math.min(610, window.height - 40, Math.max(270, content.implicitHeight + 30))
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.verticalCenter: parent.verticalCenter
      anchors.verticalCenterOffset: 24
      radius: 14
      color: theme.surfaceGlassStrong
      border.color: Qt.alpha(theme.borderSubtle, 0.58)
      border.width: 1
      clip: true

      scale: 0.955 + surfaceTransition.progress * 0.045
      opacity: surfaceTransition.progress
      transform: Translate {
        y: (1 - surfaceTransition.progress) * 20
      }

      Behavior on height {
        MotionNumberAnimation { role: MotionNumberAnimation.Content }
      }

      MouseArea {
        anchors.fill: parent
        onClicked: function(mouse) { mouse.accepted = true; }
      }

      ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: 16
        spacing: 10
        opacity: Math.max(0, Math.min(1, (surfaceTransition.progress - 0.16) / 0.84))
        transform: Translate {
          y: (1 - content.opacity) * 8
        }

        Rectangle {
          Layout.fillWidth: true
          height: 56
          radius: 10
          color: Qt.alpha(theme.surfaceGlass, 0.78)
          border.color: search.activeFocus ? root.blue : Qt.alpha(theme.borderSubtle, 0.52)
          border.width: 1

          Text {
            anchors.left: parent.left
            anchors.leftMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            text: ""
            color: root.blue
            font.family: theme.fontFamily
            font.pixelSize: 18
          }

          Row {
            id: modeSwitch
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 14

            ModeText {
              label: "Launch"
              active: root.mode === "launch"
              accent: root.yellow
              onClicked: {
                root.setMode("launch");
                search.forceActiveFocus();
              }
            }

            ModeText {
              label: "Focus"
              active: root.mode === "focus"
              accent: root.green
              onClicked: {
                root.setMode("focus");
                search.forceActiveFocus();
              }
            }
          }

          TextField {
            id: search

            anchors.left: parent.left
            anchors.leftMargin: 48
            anchors.right: modeSwitch.left
            anchors.rightMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height - 12
            background: null
            color: root.text
            selectedTextColor: theme.bgSolid
            selectionColor: root.blue
            placeholderText: root.mode === "focus"
              ? "Search open windows and tabs"
              : "Search applications or @profile"
            placeholderTextColor: root.muted
            font.family: theme.fontFamily
            font.pixelSize: 16
            font.bold: true

            onTextChanged: {
              root.selectedIndex = 0;
              root.applyFilter();
            }
            onTextEdited: {
              if (root.apps.length === 0 && root.open)
                root.retryReloadApps();
            }
            onAccepted: root.commit(false)

            Keys.onPressed: event => {
              if (event.key === Qt.Key_Escape) {
                root.closeLauncher();
                event.accepted = true;
              } else if (event.key === Qt.Key_Up || (event.key === Qt.Key_K && (event.modifiers & Qt.ControlModifier))) {
                root.moveSelection(-1);
                event.accepted = true;
              } else if (event.key === Qt.Key_Down || (event.key === Qt.Key_J && (event.modifiers & Qt.ControlModifier))) {
                root.moveSelection(1);
                event.accepted = true;
              } else if (event.key === Qt.Key_Tab) {
                root.toggleMode();
                event.accepted = true;
              } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ControlModifier)) {
                root.commit(true);
                event.accepted = true;
              }
            }
          }
        }

        ListView {
          id: list
          Layout.fillWidth: true
          Layout.preferredHeight: Math.min(420, Math.max(86, contentHeight))
          clip: true
          spacing: 4
          model: root.filtered
          currentIndex: root.selectedIndex
          interactive: contentHeight > height
          highlightFollowsCurrentItem: false

          onCurrentIndexChanged: {
            if (currentIndex >= 0)
              Qt.callLater(function() { list.positionViewAtIndex(list.currentIndex, ListView.Contain); });
          }

          highlight: Rectangle {
            width: list.width
            height: list.currentItem?.height || 0
            y: list.currentItem?.y || 0
            radius: 10
            color: Qt.alpha(root.mode === "focus" ? root.green : root.yellow, root.mode === "focus" ? 0.105 : 0.065)
            border.color: Qt.alpha(root.mode === "focus" ? root.green : root.yellow, 0.42)
            border.width: 1
            z: 1

            Behavior on y {
              MotionNumberAnimation { role: MotionNumberAnimation.FocusTravel }
            }
            Behavior on height {
              MotionNumberAnimation { role: MotionNumberAnimation.FocusTravel }
            }
            Behavior on color {
              MotionColorAnimation { role: MotionNumberAnimation.Content }
            }
            Behavior on border.color {
              MotionColorAnimation { role: MotionNumberAnimation.Content }
            }

            Rectangle {
              anchors.left: parent.left
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              width: 3
              radius: 2
              color: root.mode === "focus" ? root.green : root.yellow
            }
          }

          add: Transition {
            ParallelAnimation {
              MotionNumberAnimation {
                property: "opacity"
                from: 0
                to: 1
                role: MotionNumberAnimation.Content
              }
              MotionNumberAnimation {
                property: "x"
                from: 12
                to: 0
                role: MotionNumberAnimation.Content
              }
            }
          }
          remove: Transition {
            ParallelAnimation {
              MotionNumberAnimation {
                property: "opacity"
                to: 0
                role: MotionNumberAnimation.SurfaceExit
              }
              MotionNumberAnimation {
                property: "x"
                to: -8
                role: MotionNumberAnimation.SurfaceExit
              }
            }
          }
          displaced: Transition {
            MotionNumberAnimation {
              properties: "x,y"
              role: MotionNumberAnimation.FocusTravel
            }
          }

          delegate: ResultRow {
            required property int index
            required property var modelData
            width: list.width
            item: modelData
            selected: index === root.selectedIndex
            mode: root.mode
            onClicked: {
              root.selectedIndex = index;
              root.commit(false);
            }
          }
        }

        Rectangle {
          visible: root.filtered.length === 0
          Layout.fillWidth: true
          height: 112
          radius: 18
          color: theme.surfaceAccent
          border.color: theme.borderMuted

          Column {
            anchors.centerIn: parent
            spacing: 7

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: root.mode === "focus" ? "󰖯" : (root.launchProfileQuery() !== null ? "󰐕" : "")
              color: root.mode === "focus" ? root.green : root.blue
              font.family: theme.fontFamily
              font.pixelSize: 22
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: root.emptyResultTitle()
              color: root.text
              font.family: theme.fontFamily
              font.pixelSize: 18
              font.bold: true
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: root.emptyResultDetail()
              color: root.muted
              font.family: theme.fontFamily
              font.pixelSize: 11
            }
          }
        }

        Item {
          visible: root.filtered.length > 0
          Layout.fillWidth: true
          Layout.preferredHeight: visible ? 28 : 0

          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 1
            color: Qt.alpha(theme.borderSubtle, 0.42)
          }

          RowLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            spacing: 12

            Text {
              Layout.fillWidth: true
              text: root.mode === "focus"
                ? "↑↓ select   ·   Tab switch mode   ·   ! tabs only"
                : "↑↓ select   ·   @ profile   ·   Tab switch mode"
              color: root.muted
              font.family: theme.fontFamily
              font.pixelSize: 10
            }

            Text {
              text: {
                if (root.mode === "launch" && root.currentItem()?.kind === "profile")
                  return "Enter apply profile";
                if (root.mode === "launch")
                  return "Enter launch";
                if (root.currentItem()?.kind === "tab")
                  return "Enter focus tab";
                return "Enter focus   ·   Ctrl+Enter launch new";
              }
              color: root.mode === "focus" ? root.green : root.yellow
              font.family: theme.fontFamily
              font.pixelSize: 10
              font.bold: true
            }
          }
        }
      }
    }
  }

  component ModeText: Item {
    id: switchText
    property string label: ""
    property bool active: false
    property color accent: root.blue
    signal clicked()

    width: labelItem.implicitWidth
    height: 28

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: switchText.clicked()
    }

    Text {
      id: labelItem
      anchors.centerIn: parent
      text: switchText.label
      color: switchText.active ? switchText.accent : root.muted
      font.family: theme.fontFamily
      font.pixelSize: 12
      font.bold: true
    }

    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      width: switchText.active ? parent.width : 0
      height: 2
      radius: 1
      color: switchText.accent

      Behavior on width {
        MotionNumberAnimation { role: MotionNumberAnimation.FocusTravel }
      }
    }
  }

  component ResultRow: Rectangle {
    id: row
    property var item
    property bool selected: false
    property string mode: "launch"
    signal clicked()

    readonly property var entry: item?.entry
    readonly property var wins: item?.windows || []
    readonly property var targetWindow: item?.window || null
    readonly property var targetTab: item?.tab || null
    readonly property bool focusMode: mode === "focus"
    readonly property bool profileMode: !focusMode && item?.kind === "profile"
    readonly property bool tabMode: focusMode && item?.kind === "tab"
    readonly property bool targetActive: tabMode
      ? Boolean(targetTab?.current)
      : focusMode && root.isActiveWindow(targetWindow)
    readonly property color accent: mode === "focus" ? root.green : root.yellow
    readonly property string primaryText: focusMode
      ? (tabMode
          ? String(targetTab?.title || "Untitled tab")
          : String(targetWindow?.title || targetWindow?.initialTitle || "Untitled window"))
      : String(entry?.name || "")
    readonly property string secondaryText: {
      if (profileMode)
        return root.profileSummary(String(item?.profileId || ""));
      if (!focusMode)
        return String(entry?.genericName || entry?.comment || entry?.id || "");
      if (tabMode) {
        const group = String(targetTab?.group || "");
        const host = String(targetTab?.host || "");
        if (group && host)
          return group + " · " + host;
        return group || host || root.browserName;
      }
      const appName = String(entry?.name || entry?.id || "Unknown application");
      return root.normalize(primaryText) === root.normalize(appName) ? "" : appName;
    }

    height: focusMode ? 64 : 70
    radius: 10
    color: !selected && rowHover.containsMouse
      ? theme.surfaceAccent
      : (targetActive ? Qt.alpha(root.blue, 0.035) : "transparent")
    border.color: "transparent"
    border.width: 1
    scale: rowHover.pressed ? 0.985 : 1
    z: 2

    Behavior on color {
      MotionColorAnimation { role: MotionNumberAnimation.Feedback }
    }
    Behavior on scale {
      MotionNumberAnimation { role: MotionNumberAnimation.Feedback }
    }

    MouseArea {
      id: rowHover
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: row.clicked()
    }

    RowLayout {
      id: rowContent
      anchors.fill: parent
      anchors.leftMargin: 14
      anchors.rightMargin: 14
      spacing: 12

      Rectangle {
        Layout.preferredWidth: row.focusMode ? 40 : 44
        Layout.preferredHeight: row.focusMode ? 40 : 44
        Layout.alignment: Qt.AlignVCenter
        radius: row.focusMode ? 10 : 11
        color: row.selected
          ? Qt.alpha(row.accent, 0.18)
          : Qt.alpha(row.targetActive ? root.blue : row.accent, 0.09)
        border.color: row.selected ? Qt.alpha(row.accent, 0.28) : "transparent"
        border.width: 1

        IconImage {
          anchors.centerIn: parent
          width: row.focusMode ? 27 : 30
          height: width
          asynchronous: true
          source: Quickshell.iconPath(row.entry?.icon || "", "application-x-executable")
        }
      }

      ColumnLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        spacing: row.focusMode ? 3 : 4

        Text {
          Layout.fillWidth: true
          text: row.primaryText
          color: root.text
          elide: Text.ElideRight
          font.family: theme.fontFamily
          font.pixelSize: row.focusMode ? 14 : 16
          font.bold: true
        }

        Text {
          visible: row.secondaryText.length > 0
          Layout.fillWidth: true
          text: row.secondaryText
          color: row.focusMode && row.selected ? Qt.alpha(root.text, 0.72) : root.muted
          elide: Text.ElideRight
          font.family: theme.fontFamily
          font.pixelSize: 10
        }
      }

      RowLayout {
        visible: row.focusMode
        Layout.alignment: Qt.AlignVCenter
        spacing: 9

        Text {
          visible: row.targetActive
          text: "CURRENT"
          color: root.blue
          font.family: theme.fontFamily
          font.pixelSize: 9
          font.bold: true
        }

        Rectangle {
          height: 24
          implicitWidth: workspaceText.implicitWidth + 16
          radius: 8
          color: row.selected ? Qt.alpha(root.green, 0.10) : "transparent"
          border.color: row.selected ? Qt.alpha(root.green, 0.36) : theme.borderMuted
          border.width: 1

          Text {
            id: workspaceText
            anchors.centerIn: parent
            text: row.tabMode ? "TAB" : root.workspaceLabel(row.targetWindow)
            color: row.selected ? root.green : (row.targetActive ? root.blue : root.muted)
            font.family: theme.fontFamily
            font.pixelSize: 10
            font.bold: true
          }
        }
      }

      Rectangle {
        visible: !row.focusMode && !row.profileMode && row.wins.length > 0
        Layout.alignment: Qt.AlignVCenter
        height: 20
        implicitWidth: openLabel.implicitWidth + 14
        radius: 10
        color: Qt.alpha(root.green, 0.08)
        border.color: Qt.alpha(root.green, 0.24)

        Text {
          id: openLabel
          anchors.centerIn: parent
          text: row.wins.length + " OPEN"
          color: root.green
          font.family: theme.fontFamily
          font.pixelSize: 9
          font.bold: true
        }
      }

      Rectangle {
        visible: row.profileMode
        Layout.alignment: Qt.AlignVCenter
        height: 22
        implicitWidth: profileLabel.implicitWidth + 14
        radius: 10
        color: Qt.alpha(root.yellow, 0.08)
        border.color: Qt.alpha(root.yellow, 0.24)

        Text {
          id: profileLabel
          anchors.centerIn: parent
          text: "PROFILE"
          color: root.yellow
          font.family: theme.fontFamily
          font.pixelSize: 9
          font.bold: true
        }
      }
    }

  }
}
