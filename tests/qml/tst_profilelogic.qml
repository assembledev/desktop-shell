import QtQuick
import QtTest
import "../../src/modules/common/HyprlandWindow.js" as HyprlandWindow
import "../../src/modules/launcher/ProfileLogic.js" as ProfileLogic

TestCase {
  name: "ProfileLogic"

  readonly property var applications: [
    {
      id: "chatgpt",
      name: "ChatGPT",
      startupClass: "chatgpt",
      execString: "chatgpt %U"
    }
  ]
  readonly property var entries: [
    { id: "chatgpt.desktop", workspace: 1 }
  ]

  function test_browser_title_does_not_impersonate_application() {
    const browser = {
      address: "0x1",
      class: "librewolf",
      title: "ChatGPT - LibreWolf",
      workspace: { id: 2 }
    };
    compare(ProfileLogic.matchingWindows(applications[0], [browser]).length, 0);
  }

  function test_toplevel_snapshot_normalizes_address_and_prefers_live_workspace() {
    const snapshot = HyprlandWindow.dataForToplevel({
      address: "ABC123",
      workspace: { id: 5, name: "5" },
      lastIpcObject: {
        address: "0xabc123",
        class: "chatgpt",
        workspace: { id: 2, name: "2" }
      }
    });
    compare(snapshot.address, "0xabc123");
    compare(snapshot.workspace.id, 5);
    compare(snapshot.workspace.name, "5");

    const plan = ProfileLogic.reconcilePlan(entries, applications, [snapshot], {}, 1000, 15000);
    compare(plan.launches.length, 0);
    compare(plan.moves.length, 1);
    compare(plan.moves[0].address, "0xabc123");
    compare(plan.moves[0].workspace, 1);
  }

  function test_matching_window_moves_without_launch() {
    const existing = {
      address: "0x2",
      class: "chatgpt",
      title: "ChatGPT",
      workspace: { id: 4 }
    };
    const plan = ProfileLogic.reconcilePlan(entries, applications, [existing], {}, 1000, 15000);
    compare(plan.launches.length, 0);
    compare(plan.moves.length, 1);
    compare(plan.moves[0].address, "0x2");
    compare(plan.moves[0].workspace, 1);
  }

  function test_initial_class_is_a_technical_identity() {
    const existing = {
      address: "0x3",
      class: "changed-after-startup",
      initialClass: "chatgpt",
      workspace: { id: 1 }
    };
    compare(ProfileLogic.matchingWindows(applications[0], [existing]).length, 1);
  }

  function test_launch_lease_suppresses_fast_duplicate() {
    const first = ProfileLogic.reconcilePlan(entries, applications, [], {}, 1000, 15000);
    compare(first.launches.length, 1);
    compare(first.launches[0].id, "chatgpt.desktop");
    compare(first.launches[0].workspace, 1);

    const duplicate = ProfileLogic.reconcilePlan(entries, applications, [], first.leases, 1001, 15000);
    compare(duplicate.launches.length, 0);

    const retry = ProfileLogic.reconcilePlan(entries, applications, [], first.leases, 16001, 15000);
    compare(retry.launches.length, 1);
  }

  function test_profile_requires_resolved_desktop_entries() {
    verify(ProfileLogic.profileReady(entries, applications));
    verify(!ProfileLogic.profileReady([
      { id: "missing.desktop", workspace: 1 }
    ], applications));
  }
}
