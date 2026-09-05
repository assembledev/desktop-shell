import QtQuick
import QtTest
import "../../src/modules/bar"
import "../../src/modules/bar/BarLayout.js" as BarLayout

TestCase {
  name: "BarLayout"

  BarSpacing {
    id: space
  }

  BarSpacing {
    id: compactSpace
    compact: true
  }

  function test_wide_bar_preserves_full_clock_and_expanded_workspace() {
    const preferredWorkspaces = BarLayout.workspaceRowWidth(5, 68, 280, space.workspaceGap, true);
    const minimumRight = 556;

    compare(preferredWorkspaces, 576);
    compare(BarLayout.shouldUseCompactClock(1440, 200, preferredWorkspaces, minimumRight,
      space.edgeInset, space.centerClearance), false);
    compare(BarLayout.shouldExpandActiveWorkspace(584, 5, 68, 280, space.workspaceGap), true);
  }

  function test_constrained_bar_compacts_clock_before_side_content_collides() {
    const preferredWorkspaces = BarLayout.workspaceRowWidth(5, 68, 280, space.workspaceGap, true);
    const minimumRight = 556;

    compare(BarLayout.shouldUseCompactClock(1280, 200, preferredWorkspaces, minimumRight,
      space.edgeInset, space.centerClearance), true);
    compare(BarLayout.availableSideWidth(1280, 50, space.edgeInset, space.centerClearance), 579);
    compare(BarLayout.shouldExpandActiveWorkspace(579, 5, 68, 280, space.workspaceGap), true);
  }

  function test_active_workspace_collapses_only_when_its_content_does_not_fit() {
    compare(BarLayout.shouldExpandActiveWorkspace(575, 5, 68, 280, space.workspaceGap), false);
    compare(BarLayout.shouldExpandActiveWorkspace(576, 5, 68, 280, space.workspaceGap), true);
  }

  function test_compact_density_reduces_preferred_workspace_width() {
    compare(BarLayout.workspaceRowWidth(5, 68, 280, compactSpace.workspaceGap, true), 568);
    verify(compactSpace.workspaceGap < space.workspaceGap);
  }

  function test_network_labels_are_last_resort_after_minimum_tray() {
    const available = BarLayout.availableSideWidth(1280, 50, space.edgeInset, space.centerClearance);
    compare(available, 579);
    // Full status fits alone, but the single tray icon crosses the clearance.
    verify(BarLayout.shouldCompactNetwork(available, 560, 20, space.groupGap));
    verify(BarLayout.shouldCompactNetwork(available, 550, 34, space.groupGap));
    // Keep labels when collapsing the tray is sufficient, including exact fit.
    verify(!BarLayout.shouldCompactNetwork(available, 533, 34, space.groupGap));
    verify(!BarLayout.shouldCompactNetwork(available, 579, 0, space.groupGap));
    verify(BarLayout.shouldCompactNetwork(available, 580, 0, space.groupGap));
  }

  function test_compacted_right_side_clears_clock_for_each_tray_size() {
    // Three long provider labels push the full status past the side budget.
    // Removing their text restores room while retaining icons and lights.
    for (const centerWidth of [50, 200, 240]) {
      const available = BarLayout.availableSideWidth(1280, centerWidth,
        space.edgeInset, space.centerClearance);
      for (let count = 0; count <= 12; count++) {
        const minimumTray = BarLayout.minimumTrayWidth(count, 20, 34);
        verify(BarLayout.shouldCompactNetwork(available, 610, minimumTray, space.groupGap));
        const compactStatus = 400;
        const budget = Math.min(available - compactStatus - space.groupGap, minimumTray);
        const inline = BarLayout.inlineTrayCount(count, budget, 20,
          space.trayItemGap, space.trayTightGap, 34);
        const tray = inline === count
          ? BarLayout.rowWidth(count, 20, space.trayItemGap)
          : BarLayout.rowWidth(inline, 20, space.trayTightGap)
            + (inline > 0 ? space.trayTightGap : 0) + 34;
        const rightWidth = compactStatus + (count > 0 ? space.groupGap + tray : 0);
        verify(rightWidth <= available);
        compare(inline, count === 1 ? 1 : 0);
      }
    }
  }

  function test_tray_keeps_one_item_inline_and_uses_overflow_for_many_items() {
    compare(BarLayout.inlineTrayCount(1, 0, 20, space.trayItemGap, space.trayTightGap, 34), 1);
    compare(BarLayout.inlineTrayCount(4, 34, 20, space.trayItemGap, space.trayTightGap, 34), 0);
    compare(BarLayout.inlineTrayCount(4, 82, 20, space.trayItemGap, space.trayTightGap, 34), 2);
  }
}
