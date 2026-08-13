pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import "ProfileLogic.js" as ProfileLogic

QtObject {
  id: root

  required property string backend
  required property var applications
  required property var profiles
  required property var windows

  signal applyFinished(string profileId, bool success)

  // A launch request reserves its desktop entry briefly. This closes the gap
  // between accepting the request and Hyprland exposing the new toplevel,
  // without polling or tracking child processes.
  property var launchLeases: ({})
  readonly property int launchLeaseMs: 15000
  property string activeProfileId: ""
  property string queuedProfileId: ""
  property int applyAttempt: 0
  property var plannedLaunchIds: []
  property string stateOutput: ""
  property string stateError: ""
  property string applyOutput: ""
  property string applyError: ""
  readonly property int maxApplyAttempts: 2

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

  function snapshot(profileId) {
    const entries = profileApplications(profileId);
    return ProfileLogic.snapshot(entries, applications, windows || []);
  }

  function summary(profileId) {
    const state = snapshot(profileId);
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
      result.push({
        kind: "profile",
        profileId: profileId,
        score: score,
        usageScore: 0,
        windows: [],
        entry: {
          id: "profile-" + profileId,
          name: String(configured.label || profileId),
          icon: String(configured.icon || firstApp?.icon || "applications-other")
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
    stateOutput = "";
    stateError = "";
    stateProc.exec([backend, "launcher", "state-json"]);
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
    activeProfileId = "";
    applyAttempt = 0;
    plannedLaunchIds = [];
    applyFinished(profileId, success);

    const queued = queuedProfileId;
    queuedProfileId = "";
    if (queued.length > 0)
      Qt.callLater(function() { applyProfile(queued); });
  }

  function planFromState(raw) {
    let state;
    try {
      state = JSON.parse(raw);
    } catch (error) {
      console.error("launcher: profile state returned invalid JSON: " + error);
      finishApply(false);
      return;
    }

    const current = Array.isArray(state?.clients) ? state.clients : [];
    const entries = profileApplications(activeProfileId);

    const now = Date.now();
    const plan = ProfileLogic.reconcilePlan(
      entries,
      applications,
      current,
      launchLeases,
      now,
      launchLeaseMs
    );
    launchLeases = plan.leases;
    plannedLaunchIds = plan.launches.map(function(launch) { return launch.id; });

    console.info("launcher: profile " + activeProfileId
                 + " snapshot=" + current.length
                 + " moves=" + plan.moves.length
                 + " launches=" + plan.launches.length
                 + " attempt=" + applyAttempt);

    if (plan.moves.length === 0 && plan.launches.length === 0) {
      finishApply(true);
      return;
    }

    applyOutput = "";
    applyError = "";
    applyProc.exec([
      backend,
      "launcher",
      "apply-plan",
      JSON.stringify({ moves: plan.moves, launches: plan.launches })
    ]);
  }

  Process {
    id: stateProc
    stdout: StdioCollector {
      onStreamFinished: root.stateOutput = text
    }
    stderr: StdioCollector {
      onStreamFinished: root.stateError = text
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        console.error("launcher: profile state query failed: " + root.stateError.trim());
        root.finishApply(false);
        return;
      }
      root.planFromState(root.stateOutput);
    }
  }

  Process {
    id: applyProc
    stdout: StdioCollector {
      onStreamFinished: root.applyOutput = text
    }
    stderr: StdioCollector {
      onStreamFinished: root.applyError = text
    }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        console.info("launcher: profile " + root.activeProfileId
                     + " applied " + root.applyOutput.trim());
        root.finishApply(true);
        return;
      }

      console.error("launcher: profile " + root.activeProfileId
                    + " apply failed: " + root.applyError.trim());
      root.clearPlannedLaunchLeases();
      if (root.applyAttempt < root.maxApplyAttempts) {
        const profileId = root.activeProfileId;
        Qt.callLater(function() { root.beginApply(profileId, root.applyAttempt + 1); });
      } else {
        root.finishApply(false);
      }
    }
  }
}
