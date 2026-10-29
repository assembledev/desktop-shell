import QtQuick
import QtTest
import "../../src/modules/common"

TestCase {
  name: "MotionTransition"
  MotionTransition { id: motion }

  function test_snap_dismisses_an_active_transition() {
    failOnWarning(/.*/);
    motion.requested = true;
    wait(50);
    motion.requested = false;
    motion.snapDismissed();
    compare(motion.progress, 0);
    verify(!motion.presented);
    verify(!motion.running);
    wait(300);
    compare(motion.progress, 0);
    verify(!motion.presented);
  }
}
