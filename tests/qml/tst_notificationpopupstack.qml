import QtQuick
import QtTest
import "../../src/modules/control_center" as ControlCenter

TestCase {
  id: suite
  name: "NotificationPopupStack"
  width: 400
  height: 600
  visible: true
  when: windowShown

  ListModel {
    id: source
  }
  ControlCenter.NotificationPopupModel {
    id: rows
    model: source
    outputName: "one"
  }
  ControlCenter.NotificationPopupStack {
    id: stack
    width: 386
    Repeater {
      id: repeater
      model: rows
      delegate: Rectangle {
        required property int popupId
        width: stack.width
        height: 86
        implicitHeight: 86
        color: "#23283b"
      }
    }
  }

  function add(id) {
    source.insert(0, {popupId: id, outputName: "one"});
  }

  function init() {
    source.clear();
    wait(0);
  }

  function test_arrivalAnimatesExistingCardDown() {
    add(1);
    tryCompare(stack, "height", 86);
    const first = repeater.itemAt(0);
    compare(first.y, 0);
    add(2);
    wait(48);
    compare(repeater.itemAt(1), first);
    verify(first.y > 0 && first.y < 96, "arrival must move the existing card through intermediate positions: " + first.y);
    compare(first.width, 386);
    compare(first.height, 86);
    compare(first.scale, 1);
    compare(first.opacity, 1);
    tryCompare(first, "y", 96);
    tryCompare(stack, "height", 182);
  }

  function test_removalAnimatesSurvivorUp() {
    add(1);
    add(2);
    const survivor = repeater.itemAt(1);
    tryCompare(survivor, "y", 96);
    source.remove(0);
    wait(48);
    compare(repeater.itemAt(0), survivor);
    verify(survivor.y > 0 && survivor.y < 96, "removal must move the survivor through intermediate positions: " + survivor.y);
    compare(survivor.width, 386);
    compare(survivor.height, 86);
    compare(survivor.scale, 1);
    compare(survivor.opacity, 1);
    tryCompare(survivor, "y", 0);
  }

  function test_bottomRemovalDoesNotMoveOrResizeSurvivor() {
    add(1);
    add(2);
    const survivor = repeater.itemAt(0);
    tryCompare(stack, "height", 182);
    source.remove(1);
    for (let i = 0; i < 18; i++) {
      wait(16);
      compare(repeater.itemAt(0), survivor);
      compare(survivor.y, 0);
      compare(survivor.width, 386);
      compare(survivor.height, 86);
      compare(survivor.scale, 1);
      compare(survivor.opacity, 1);
    }
  }

  function test_rapidChangesContinueFromCurrentPosition() {
    add(1);
    waitForRendering(stack);
    const survivor = repeater.itemAt(0);
    add(2);
    wait(48);
    const before = survivor.y;
    verify(before > 0 && before < 96);
    add(3);
    compare(repeater.itemAt(2), survivor);
    fuzzyCompare(survivor.y, before, 1);
    wait(48);
    verify(survivor.y > before && survivor.y < 192);
    source.remove(0);
    tryCompare(survivor, "y", 96);
  }
}
