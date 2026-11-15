import QtQuick
import "../common"

Column {
  spacing: 10

  function activateOldest(repeater) {
    // Rows are newest first. Closing cards are no longer pending.
    for (let i = repeater.count - 1; i >= 0; i--) {
      const toast = repeater.itemAt(i);
      if (toast && !toast.closing) {
        toast.activateDefault();
        return;
      }
    }
  }

  move: Transition {
    MotionNumberAnimation {
      properties: "y"
      role: MotionNumberAnimation.FocusTravel
    }
  }
}
