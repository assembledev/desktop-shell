pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../common/HyprlandWindow.js" as HyprlandWindow
import "ProfileLogic.js" as ProfileLogic

QtObject {
  id: root

  required property string backend
  required property var applications
  required property var compositor
  required property var profiles

  // A launch request reserves its desktop entry briefly. This closes the gap
  // between accepting the request and Hyprland exposing the new toplevel,
  // without polling or tracking child processes.
  property var launchLeases: ({})
  readonly property int launchLeaseMs: 15000

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

  function snapshot(profileId) {
    const entries = profileApplications(profileId);
    return ProfileLogic.snapshot(entries, applications, currentWindows());
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
      return;
    }
    if (!profileReady(profileId)) {
      console.error("launcher: desktop entries are not ready for profile: " + profileId);
      return;
    }

    const now = Date.now();
    const plan = ProfileLogic.reconcilePlan(
      entries,
      applications,
      currentWindows(),
      launchLeases,
      now,
      launchLeaseMs
    );
    launchLeases = plan.leases;

    for (const move of plan.moves)
      compositor.moveWindowToWorkspace(move.address, move.workspace);
    for (const launch of plan.launches) {
      Quickshell.execDetached([
        backend,
        "launcher",
        "launch-in-workspace",
        launch.id,
        String(launch.workspace)
      ]);
    }
  }
}
