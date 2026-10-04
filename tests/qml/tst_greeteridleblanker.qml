import QtQuick
import QtTest
import "../../src/modules/greeter"

TestCase {
  id: suite
  name: "GreeterIdleBlanker"
  width: 320
  height: 240
  visible: true
  when: windowShown

  Component {
    id: surfaceComponent

    Item {
      id: surface
      width: 300
      height: 220
      property int keys: 0
      property int clicks: 0
      property alias blanker: idleBlanker

      Item {
        id: input
        anchors.fill: parent
        visible: !idleBlanker.blanked
        focus: true
        Keys.onPressed: event => {
          idleBlanker.activity();
          surface.keys++;
          event.accepted = true;
        }

        MouseArea {
          anchors.fill: parent
          onPressed: idleBlanker.activity()
          onClicked: surface.clicks++
        }
      }

      IdleBlanker {
        id: idleBlanker
        anchors.fill: parent
        timeout: 250
        onResumed: input.forceActiveFocus()
      }

      Component.onCompleted: input.forceActiveFocus()
    }
  }

  function makeSurface() {
    const surface = createTemporaryObject(surfaceComponent, suite);
    verify(surface);
    mouseMove(surface, 20, 20);
    surface.blanker.activity();
    return surface;
  }

  function test_blanksAfterIdle() {
    const surface = makeSurface();
    compare(surface.blanker.blanked, false);
    tryCompare(surface.blanker, "blanked", true, 1000);
    verify(surface.blanker.activeFocus);
    const frame = grabImage(surface);
    compare(frame.pixel(150, 110), "#000000");
  }

  function test_activityRestartsDeadline() {
    const surface = makeSurface();
    wait(150);
    keyClick(Qt.Key_Shift);
    wait(150);
    compare(surface.blanker.blanked, false);
    tryCompare(surface.blanker, "blanked", true, 1000);
  }

  function test_wakeKeyIsConsumed_data() {
    return [
      { tag: "text", key: Qt.Key_A },
      { tag: "submit", key: Qt.Key_Return },
      { tag: "modifier", key: Qt.Key_Shift }
    ];
  }

  function test_wakeKeyIsConsumed(row) {
    const surface = makeSurface();
    tryCompare(surface.blanker, "blanked", true, 1000);
    keyClick(row.key);
    compare(surface.blanker.blanked, false);
    compare(surface.keys, 0);
    keyClick(Qt.Key_B);
    compare(surface.keys, 1);
  }

  function test_wakeClickIsConsumed_data() {
    return [
      { tag: "left", button: Qt.LeftButton },
      { tag: "right", button: Qt.RightButton },
      { tag: "middle", button: Qt.MiddleButton }
    ];
  }

  function test_wakeClickIsConsumed(row) {
    const surface = makeSurface();
    tryCompare(surface.blanker, "blanked", true, 1000);
    mouseClick(surface, 20, 20, row.button);
    compare(surface.blanker.blanked, false);
    compare(surface.clicks, 0);
    mouseClick(surface, 20, 20);
    compare(surface.clicks, 1);
  }

  function test_touchWakesWithoutClicking() {
    const surface = makeSurface();
    tryCompare(surface.blanker, "blanked", true, 1000);
    touchEvent(surface).press(0, surface, 20, 20).commit();
    touchEvent(surface).release(0, surface, 20, 20).commit();
    tryCompare(surface.blanker, "blanked", false);
    compare(surface.clicks, 0);
  }

  function test_pointerMovementRestartsDeadline() {
    const surface = makeSurface();
    wait(150);
    mouseMove(surface, 25, 20);
    wait(150);
    compare(surface.blanker.blanked, false);
    mouseMove(surface, 30, 20);
    wait(150);
    compare(surface.blanker.blanked, false);
    tryCompare(surface.blanker, "blanked", true, 1000);
  }

  function test_stationaryPointerStaysBlank() {
    const surface = makeSurface();
    tryCompare(surface.blanker, "blanked", true, 1000);
    mouseMove(surface, 20, 20);
    compare(surface.blanker.blanked, true);
    mouseMove(surface, 25, 20);
    compare(surface.blanker.blanked, false);
  }

  function test_wheelWakes() {
    const surface = makeSurface();
    tryCompare(surface.blanker, "blanked", true, 1000);
    mouseWheel(surface, 20, 20, 0, 120);
    compare(surface.blanker.blanked, false);
  }

  function test_authenticationSuspendsBlanking() {
    const surface = makeSurface();
    surface.blanker.suspended = true;
    keyClick(Qt.Key_A);
    wait(350);
    compare(surface.blanker.blanked, false);
    surface.blanker.suspended = false;
    tryCompare(surface.blanker, "blanked", true, 1000);
  }

  function test_multipleIdleWakeCycles() {
    const surface = makeSurface();
    for (let cycle = 0; cycle < 3; cycle++) {
      tryCompare(surface.blanker, "blanked", true, 1000);
      keyClick(Qt.Key_A);
      compare(surface.blanker.blanked, false);
      compare(surface.keys, 0);
    }
  }
}
