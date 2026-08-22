import QtQuick
import QtTest
import "../../src/modules/bar/BarLayout.js" as BarLayout

TestCase {
  name: "BarLayout"

  function test_wide_bar_preserves_full_clock_and_expanded_workspace() {
    const preferredWorkspaces = BarLayout.workspaceRowWidth(5, 68, 280, 6, true);
    const minimumRight = 556;

    compare(preferredWorkspaces, 576);
    compare(BarLayout.shouldUseCompactClock(1440, 200, preferredWorkspaces, minimumRight, 15, 20), false);
    compare(BarLayout.shouldExpandActiveWorkspace(585, 5, 68, 280, 6), true);
  }

  function test_constrained_bar_compacts_clock_before_side_content_collides() {
    const preferredWorkspaces = BarLayout.workspaceRowWidth(5, 68, 280, 6, true);
    const minimumRight = 556;

    compare(BarLayout.shouldUseCompactClock(1280, 200, preferredWorkspaces, minimumRight, 15, 20), true);
    compare(BarLayout.availableSideWidth(1280, 50, 15, 20), 580);
    compare(BarLayout.shouldExpandActiveWorkspace(580, 5, 68, 280, 6), true);
  }

  function test_active_workspace_collapses_only_when_its_content_does_not_fit() {
    compare(BarLayout.shouldExpandActiveWorkspace(575, 5, 68, 280, 6), false);
    compare(BarLayout.shouldExpandActiveWorkspace(576, 5, 68, 280, 6), true);
  }

  function test_tray_keeps_one_item_inline_and_uses_overflow_for_many_items() {
    compare(BarLayout.inlineTrayCount(1, 0, 20, 8, 4, 34), 1);
    compare(BarLayout.inlineTrayCount(4, 34, 20, 8, 4, 34), 0);
    compare(BarLayout.inlineTrayCount(4, 82, 20, 8, 4, 34), 2);
  }
}
