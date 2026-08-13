import QtQuick
import QtTest
import "../../src/modules/common/HyprlandWindow.js" as HyprlandWindow
import "../../src/modules/launcher/LauncherSearch.js" as LauncherSearch
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

  function test_hidden_client_keeps_identity_but_is_not_a_manageable_target() {
    const hidden = {
      address: "0xaaa",
      class: "chatgpt",
      hidden: true,
      workspace: { id: 1 }
    };
    verify(LauncherSearch.appWindowTechnicalIdentityScore(applications[0], hidden) >= 0);
    compare(LauncherSearch.appWindowManageableTechnicalIdentityScore(applications[0], hidden), -1);
    compare(LauncherSearch.appWindowIdentityScore(applications[0], hidden), -1);
    compare(ProfileLogic.matchingWindows(applications[0], [hidden]).length, 0);
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

  function test_desktop_suffix_in_entry_basename_is_preserved() {
    const telegram = {
      id: "org.telegram.desktop",
      name: "Telegram Desktop",
      startupClass: "",
      execString: "telegram-desktop"
    };
    const telegramEntry = {
      id: "org.telegram.desktop.desktop",
      workspace: 5
    };
    const existing = {
      address: "0x4",
      class: "org.telegram.desktop",
      initialClass: "org.telegram.desktop",
      title: "Telegram",
      workspace: { id: 2 }
    };

    compare(ProfileLogic.matchingWindows(telegram, [existing]).length, 1);
    const plan = ProfileLogic.reconcilePlan([telegramEntry], [telegram], [existing], {}, 1000, 15000);
    compare(plan.launches.length, 0);
    compare(plan.moves.length, 1);
    compare(plan.moves[0].address, "0x4");
    compare(plan.moves[0].workspace, 5);
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

  function test_usage_history_merges_launches_without_losing_disk_state() {
    const disk = {
      "chatgpt.desktop": { launchCount: 4, lastLaunch: 100 },
      "librewolf.desktop": { launchCount: 2, lastLaunch: 80 }
    };
    let pending = LauncherSearch.recordUsage({}, "chatgpt.desktop", 120);
    pending = LauncherSearch.recordUsage(pending, "org.telegram.desktop.desktop", 121);
    const merged = LauncherSearch.mergeUsageHistory(disk, pending);
    compare(merged["chatgpt.desktop"].launchCount, 5);
    compare(merged["chatgpt.desktop"].lastLaunch, 120);
    compare(merged["librewolf.desktop"].launchCount, 2);
    compare(merged["org.telegram.desktop.desktop"].launchCount, 1);
  }

  function test_active_window_move_is_ordered_last() {
    const moves = [
      { address: "0xaaa", workspace: 1 },
      { address: "0xbbb", workspace: 2 },
      { address: "0xccc", workspace: 3 }
    ];
    const ordered = ProfileLogic.orderedMoves(moves, "BBB");
    compare(ordered.length, 3);
    compare(ordered[0].address, "0xaaa");
    compare(ordered[1].address, "0xccc");
    compare(ordered[2].address, "0xbbb");
  }

  function test_movewindow_event_is_strictly_parsed() {
    const moved = ProfileLogic.movedWindowEvent("ABC123,5,5");
    verify(moved !== null);
    compare(moved.address, "0xabc123");
    compare(moved.workspace, 5);
    compare(ProfileLogic.movedWindowEvent("bad address,5,5"), null);
    compare(ProfileLogic.movedWindowEvent("abc123,0,0"), null);
    compare(ProfileLogic.movedWindowEvent("abc123"), null);
  }

  function test_move_completion_uses_live_workspace() {
    const move = { address: "0xabc", workspace: 5 };
    verify(ProfileLogic.moveApplied(move, [{
      address: "ABC",
      workspace: { id: 5 }
    }]));
    verify(!ProfileLogic.moveApplied(move, [{
      address: "0xabc",
      workspace: { id: 2 }
    }]));
    verify(ProfileLogic.movesApplied([
      move,
      { address: "0xdef", workspace: 3 }
    ], [
      { address: "0xabc", workspace: { id: 5 } },
      { address: "def", workspace: { id: 3 } }
    ]));
  }

  function test_profile_requires_resolved_desktop_entries() {
    verify(ProfileLogic.profileReady(entries, applications));
    verify(!ProfileLogic.profileReady([
      { id: "missing.desktop", workspace: 1 }
    ], applications));
  }
}
