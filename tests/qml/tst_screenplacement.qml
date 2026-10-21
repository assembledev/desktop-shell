import QtQuick
import QtTest
import "../../src/modules/common"

TestCase {
  name: "ScreenPlacement"

  QtObject {
    id: config
    property var screens: []
    property string focusedOutputName: ""
    property string outputName: ""
  }
  QtObject {
    id: left
    property string name: "left"
    property int width: 1920
    property real scale: 1
  }
  QtObject {
    id: right
    property string name: "right"
    property int width: 1440
    property real scale: 2
  }
  ScreenPlacement { id: placement; configuration: config }
  SignalSpy { id: removed; target: placement; signalName: "removed" }

  function init() {
    placement.clear();
    config.screens = [left, right];
    config.focusedOutputName = "right";
    config.outputName = "left";
    right.width = 1440;
    right.scale = 2;
    removed.clear();
  }

  function test_closed_surface_has_no_output() {
    compare(placement.screen, null);
  }

  function test_keyboard_uses_focused_output_before_configured_fallback() {
    compare(placement.capture(), right);
    compare(placement.screen, right);
  }

  function test_pointer_uses_originating_surface() {
    compare(placement.capture(left), left);
  }

  function test_focus_changes_do_not_move_open_surface() {
    placement.capture();
    config.focusedOutputName = "left";
    compare(placement.screen, right);
    compare(placement.capture(), left);
  }

  function test_geometry_and_scale_remain_live() {
    placement.capture();
    right.width = 900;
    right.scale = 1.5;
    compare(placement.screen.width, 900);
    compare(placement.screen.scale, 1.5);
  }

  function test_missing_focus_uses_configured_fallback() {
    config.focusedOutputName = "missing";
    compare(placement.capture(), left);
    config.outputName = "missing";
    compare(placement.capture(), left);
  }

  function test_unplug_cancels_without_moving_to_other_output() {
    placement.capture();
    config.screens = [left];
    compare(placement.screen, null);
    tryCompare(removed, "count", 1);
    config.screens = [left, right];
    compare(placement.screen, null);
    config.focusedOutputName = "left";
    compare(placement.capture(), left);
  }

  function test_output_reordering_keeps_placement() {
    placement.capture(left);
    config.screens = [right, left];
    compare(placement.screen, left);
    compare(removed.count, 0);
  }

  function test_replaced_screen_object_is_resolved_by_name() {
    placement.capture(right);
    config.screens = [left, { name: "right", width: 900, scale: 2 }];
    compare(placement.screen.width, 900);
    compare(removed.count, 0);
  }

  function test_queued_invocation_is_cancelled_when_its_output_is_gone() {
    const origin = right;
    config.screens = [left];
    compare(placement.capture(origin), null);
    compare(placement.screen, null);
  }

  function test_new_invocation_survives_an_earlier_queued_removal() {
    placement.capture(right);
    config.screens = [left];
    config.focusedOutputName = "left";
    placement.capture();
    wait(0);
    compare(placement.screen, left);
    compare(removed.count, 0);
  }

  function test_no_outputs_does_not_capture() {
    config.screens = [];
    compare(placement.capture(), null);
    compare(placement.screen, null);
    compare(removed.count, 0);
  }
}
