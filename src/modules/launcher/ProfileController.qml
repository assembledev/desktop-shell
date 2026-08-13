pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../common"
import "../common/HyprlandWindow.js" as HyprlandWindow
import "ProfileLogic.js" as ProfileLogic

Scope {
  id: root

  required property var applications
  required property var profiles

  signal applyFinished(string profileId, bool success)

  // A launch request reserves its desktop entry briefly. This closes the gap
  // between dispatch and Hyprland exposing the new toplevel without watching
  // the launched process.
  property var launchLeases: ({})
  readonly property int launchLeaseMs: 15000
  readonly property int maxApplyAttempts: 2
  readonly property int moveTimeoutMs: 750

  property string activeProfileId: ""
  property string queuedProfileId: ""
  property int applyAttempt: 0
  property var plannedLaunchIds: []
  property var requestedMoves: []
  property var moveQueue: []
  property var currentMove: null
  property var pendingLaunches: []

  HyprlandAdapter { id: hyprland }
  HyprlandClientSnapshot {
    id: clientSnapshot
    onSucceeded: function(clients) { root.preparePlan(clients); }
    onFailed: function(reason) { root.retryApply("native snapshot failed: " + reason); }
  }

  function profile(profileId) {
    const configured = profiles?.[profileId];
    return configured && typeof configured === "object" ? configured : null;
  }

  function profileApplications(profileId) {
    const configured = profile(profileId);
    return Array.isArray(configured?.applications) ? configured.applications : [];
  }

  function applicationForEntryId(entryId) {
    return ProfileLogic.applicationForEntryId(applications, entryId);
  }

  function profileReady(profileId) {
    const entries = profileApplications(profileId);
    return ProfileLogic.profileReady(entries, applications);
  }

  function currentWindows() {
    return (Hyprland.toplevels.values || []).map(HyprlandWindow.dataForToplevel);
  }

  function activeWindowAddress() {
    const active = Hyprland.activeToplevel
      || (Hyprland.toplevels.values || []).find(function(toplevel) { return toplevel?.activated; });
    return HyprlandWindow.normalizedAddress(active?.address || "");
  }

  function snapshot(profileId) {
    const entries = profileApplications(profileId);
    return ProfileLogic.snapshot(entries, applications, currentWindows());
  }

  function summary(profileId) {
    return summaryText(snapshot(profileId));
  }

  function summaryText(state) {
    if (state.total === 0)
      return "Empty profile";
    if (state.placed === state.total)
      return state.total + "/" + state.total + " ready";
    if (state.open === state.total)
      return state.open + "/" + state.total + " open · restore layout";
    return state.open + "/" + state.total + " open · launch and restore layout";
  }

  function resultEntries(query) {
    const result = [];
    const windows = currentWindows();
    for (const profileId of Object.keys(profiles || {}).sort()) {
      const configured = profile(profileId);
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

      const firstSpec = configured.applications[0];
      const firstApp = applicationForEntryId(firstSpec?.id);
      const configuredIcon = String(configured.icon || "");
      const icon = configuredIcon.length > 0 && Quickshell.hasThemeIcon(configuredIcon)
        ? configuredIcon
        : String(firstApp?.icon || "applications-other");
      const applicationNames = configured.applications.map(function(spec) {
        return String(applicationForEntryId(spec.id)?.name || "");
      }).filter(function(name) { return name.length > 0; });
      const description = String(configured.description || applicationNames.join(", "));
      result.push({
        kind: "profile",
        profileId: profileId,
        description: description,
        summary: summaryText(ProfileLogic.snapshot(configured.applications, applications, windows)),
        score: score,
        usageScore: 0,
        windows: [],
        entry: {
          id: "profile-" + profileId,
          name: String(configured.label || profileId),
          icon: icon
        }
      });
    }
    return result;
  }

  function applyProfile(profileId) {
    const entries = profileApplications(profileId);
    if (entries.length === 0) {
      console.error("launcher: unknown or empty profile: " + profileId);
      return false;
    }
    if (!profileReady(profileId)) {
      console.error("launcher: desktop entries are not ready for profile: " + profileId);
      return false;
    }

    if (activeProfileId.length > 0) {
      if (profileId !== activeProfileId)
        queuedProfileId = profileId;
      return true;
    }

    beginApply(profileId, 1);
    return true;
  }

  function beginApply(profileId, attempt) {
    activeProfileId = profileId;
    applyAttempt = attempt;
    currentMove = null;
    requestedMoves = [];
    moveQueue = [];
    pendingLaunches = [];
    moveTimeout.stop();

    if (!clientSnapshot.request())
      retryApply("native snapshot request is already active");
  }

  function clearPlannedLaunchLeases() {
    const nextLeases = Object.assign({}, launchLeases || {});
    for (const entryId of plannedLaunchIds)
      delete nextLeases[entryId];
    launchLeases = nextLeases;
    plannedLaunchIds = [];
  }

  function finishApply(success) {
    const profileId = activeProfileId;
    moveTimeout.stop();
    activeProfileId = "";
    applyAttempt = 0;
    plannedLaunchIds = [];
    requestedMoves = [];
    moveQueue = [];
    currentMove = null;
    pendingLaunches = [];
    applyFinished(profileId, success);

    const queued = queuedProfileId;
    queuedProfileId = "";
    if (queued.length > 0)
      Qt.callLater(function() { applyProfile(queued); });
  }

  function retryApply(reason) {
    console.error("launcher: profile " + activeProfileId + " apply failed: " + reason);
    clearPlannedLaunchLeases();
    moveTimeout.stop();
    currentMove = null;
    moveQueue = [];
    pendingLaunches = [];

    if (applyAttempt < maxApplyAttempts) {
      const profileId = activeProfileId;
      Qt.callLater(function() { beginApply(profileId, applyAttempt + 1); });
    } else {
      finishApply(false);
    }
  }

  function preparePlan(current) {
    if (activeProfileId.length === 0)
      return;

    const entries = profileApplications(activeProfileId);
    const plan = ProfileLogic.reconcilePlan(
      entries,
      applications,
      current,
      launchLeases,
      Date.now(),
      launchLeaseMs
    );
    launchLeases = plan.leases;
    plannedLaunchIds = plan.launches.map(function(launch) { return launch.id; });
    requestedMoves = ProfileLogic.orderedMoves(plan.moves, activeWindowAddress());
    moveQueue = requestedMoves.slice();
    pendingLaunches = plan.launches.slice();

    console.info("launcher: profile " + activeProfileId
                 + " snapshot=" + current.length
                 + " moves=" + requestedMoves.length
                 + " launches=" + pendingLaunches.length
                 + " attempt=" + applyAttempt);

    dispatchNextMove();
  }

  function dispatchNextMove() {
    if (currentMove !== null)
      return;
    if (moveQueue.length === 0) {
      completePlan();
      return;
    }

    const next = moveQueue[0];
    moveQueue = moveQueue.slice(1);
    if (ProfileLogic.moveApplied(next, currentWindows())) {
      Qt.callLater(function() { dispatchNextMove(); });
      return;
    }

    currentMove = next;
    hyprland.moveWindowToWorkspace(next.address, next.workspace);
    moveTimeout.restart();
  }

  function completePlan() {
    if (!ProfileLogic.movesApplied(requestedMoves, currentWindows())) {
      retryApply("native move verification failed");
      return;
    }

    for (const launch of pendingLaunches) {
      if (!hyprland.launchDesktopEntryInWorkspace(launch.id, launch.workspace)) {
        retryApply("invalid native launch request");
        return;
      }
    }

    console.info("launcher: profile " + activeProfileId
                 + " applied moved=" + requestedMoves.length
                 + " launched=" + pendingLaunches.length);
    finishApply(true);
  }

  Timer {
    id: moveTimeout
    interval: root.moveTimeoutMs
    repeat: false
    onTriggered: {
      if (root.currentMove !== null
          && ProfileLogic.moveApplied(root.currentMove, root.currentWindows())) {
        root.currentMove = null;
        Qt.callLater(function() { root.dispatchNextMove(); });
      } else {
        root.retryApply("native move event timed out");
      }
    }
  }

  Connections {
    target: Hyprland

    function onRawEvent(event) {
      if (event.name !== "movewindowv2" || root.currentMove === null)
        return;

      const moved = ProfileLogic.movedWindowEvent(event.data);
      if (moved === null || moved.address !== root.currentMove.address)
        return;
      if (moved.workspace !== root.currentMove.workspace) {
        root.retryApply("window moved to an unexpected workspace");
        return;
      }

      moveTimeout.stop();
      root.currentMove = null;
      Qt.callLater(function() { root.dispatchNextMove(); });
    }
  }
}
