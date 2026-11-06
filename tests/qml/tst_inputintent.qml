import QtQuick
import QtTest
import "../../src/modules/common"

TestCase {
  name: "InputIntent"

  InputIntent {
    id: intent
    width: 100
    height: 100
  }

  function init() {
    intent.pointerActive = false;
    intent.hasPointerPosition = false;
    intent.lastPointerScenePosition = Qt.point(0, 0);
    intent.latestPointerScenePosition = Qt.point(0, 0);
  }

  function test_slow_pointer_movement_accumulates() {
    intent.observePointerScenePosition(Qt.point(0, 0));
    intent.observePointerScenePosition(Qt.point(0.2, 0));
    intent.observePointerScenePosition(Qt.point(0.4, 0));
    compare(intent.pointerActive, false);
    intent.observePointerScenePosition(Qt.point(0.6, 0));
    compare(intent.pointerActive, true);
  }

  function test_keyboard_claim_discards_unaccepted_motion() {
    intent.observePointerScenePosition(Qt.point(0, 0));
    intent.observePointerScenePosition(Qt.point(0.4, 0));
    intent.claimKeyboard();
    intent.observePointerScenePosition(Qt.point(0.6, 0));
    compare(intent.pointerActive, false);
    intent.observePointerScenePosition(Qt.point(1, 0));
    compare(intent.pointerActive, true);
  }

  function test_jitter_does_not_accumulate_distance() {
    intent.observePointerScenePosition(Qt.point(0, 0));
    for (let i = 0; i < 10; i++) {
      intent.observePointerScenePosition(Qt.point(0.2, 0));
      intent.observePointerScenePosition(Qt.point(-0.2, 0));
    }
    compare(intent.pointerActive, false);
  }

  function test_stationary_pointer_does_not_claim_intent() {
    intent.observePointerScenePosition(Qt.point(40, 50));
    compare(intent.pointerActive, false);

    intent.observePointerScenePosition(Qt.point(40, 50));
    compare(intent.pointerActive, false);
  }

  function test_real_pointer_movement_claims_intent() {
    intent.observePointerScenePosition(Qt.point(40, 50));
    intent.observePointerScenePosition(Qt.point(41, 50));
    compare(intent.pointerActive, true);
  }

  function test_keyboard_keeps_authority_until_pointer_moves() {
    intent.observePointerScenePosition(Qt.point(40, 50));
    intent.observePointerScenePosition(Qt.point(41, 50));
    compare(intent.pointerActive, true);

    intent.claimKeyboard();
    compare(intent.pointerActive, false);

    intent.observePointerScenePosition(Qt.point(41, 50));
    compare(intent.pointerActive, false);

    intent.observePointerScenePosition(Qt.point(41, 51));
    compare(intent.pointerActive, true);
  }
}
