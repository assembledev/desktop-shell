pragma ComponentBehavior: Bound

import QtQuick
import "../common"

FocusScope {
  id: root

  property int timeout: 600000
  property bool suspended: false
  property bool blanked: false

  signal resumed()

  function activity() {
    const wasBlanked = blanked;
    blanked = false;
    if (suspended)
      idleTimer.stop();
    else
      idleTimer.restart();
    if (wasBlanked)
      resumed();
  }

  Component.onCompleted: activity()
  onSuspendedChanged: activity()
  onBlankedChanged: if (blanked) forceActiveFocus()

  Timer {
    id: idleTimer
    interval: root.timeout
    repeat: false
    onTriggered: root.blanked = true
  }

  // Observe real scene movement across child controls without grabbing input.
  InputIntent {
    surface: root.parent
    onPointerActivity: root.activity()
  }

  Keys.enabled: root.blanked
  Keys.onPressed: event => {
    root.activity();
    event.accepted = true;
  }

  // Keep the display link active; waking only restores the greeter's surface.
  Rectangle {
    anchors.fill: parent
    visible: root.blanked
    color: "black"

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.AllButtons
      cursorShape: Qt.BlankCursor
      onPressed: mouse => {
        root.activity();
        mouse.accepted = true;
      }
      onWheel: wheel => {
        root.activity();
        wheel.accepted = true;
      }
    }
  }
}
