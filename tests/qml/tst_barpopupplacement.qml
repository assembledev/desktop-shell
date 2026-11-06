import QtQuick
import QtTest
import "../../src/modules/common"

TestCase {
  id: test
  name: "BarPopupPlacement"
  when: windowShown
  visible: true
  width: 1200
  height: 800

  Item {
    id: group
    x: 600
    Item { id: trigger; x: 40; width: 24; height: 37 }
  }
  Item { id: shelf; x: 400; y: 2; width: 200; height: 100 }
  BarPopupPlacement {
    id: placement
    trigger: trigger
    screenWidth: 1200
    screenHeight: 800
    barHeight: 37
    preferredWidth: 320
    active: true
  }
  SignalSpy { id: lost; target: placement; signalName: "anchorLost" }

  function init() {
    placement.active = false;
    group.x = 600; group.visible = true; group.scale = 1;
    trigger.x = 40; trigger.width = 24; trigger.scale = 1;
    placement.trigger = trigger;
    placement.screenWidth = 1200; placement.screenHeight = 800;
    placement.barHeight = 37; placement.surfaceTop = 37;
    placement.preferredWidth = 320;
    placement.belowItem = null; placement.sourceTop = 0;
    placement.active = true;
    lost.clear();
  }
  function test_layout_changes_follow_ancestors_and_width() {
    compare(placement.x, 492);
    group.x = 500;
    compare(placement.x, 392);
    trigger.width = 80;
    compare(placement.x, 420);
    trigger.scale = 0.86; group.scale = 1.08;
    compare(placement.x, 420);
  }
  function test_edges_and_narrow_logical_output() {
    group.x = 0; trigger.x = 0;
    compare(placement.x, 12);
    group.x = 1180;
    compare(placement.x, 868);
    placement.screenWidth = 280;
    compare(placement.width, 256);
    compare(placement.x, 12);
  }
  function test_portrait_and_surface_coordinates() {
    placement.barHeight = 88; placement.surfaceTop = 88;
    compare(placement.y, 2);
    compare(placement.maximumHeight, 698);
    placement.surfaceTop = 0;
    compare(placement.y, 90);
  }
  function test_shelf_attachment_ignores_visual_scale() {
    placement.belowItem = shelf; placement.sourceTop = 37;
    placement.surfaceTop = 0;
    compare(placement.y, 141);
    shelf.scale = 0.9;
    compare(placement.y, 141);
    shelf.height = 140;
    compare(placement.y, 181);
    shelf.height = 100; shelf.scale = 1;
  }
  function test_keyboard_fallback_and_no_false_loss() {
    placement.active = false;
    placement.trigger = null;
    placement.active = true;
    compare(placement.x, 440);
    wait(0);
    compare(lost.count, 0);
  }
  function test_hidden_ancestor_cancels() {
    group.visible = false;
    tryCompare(lost, "count", 1);
  }
  function test_removed_anchor_cancels() {
    placement.trigger = null;
    tryCompare(lost, "count", 1);
  }
}
