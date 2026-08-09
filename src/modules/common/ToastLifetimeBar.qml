import QtQuick

Rectangle {
  id: root

  property int duration: 0
  property bool persistent: false
  required property color trackColor
  required property color accentColor
  property color hoverAccentColor: accentColor
  readonly property bool hovered: controller.hovered
  readonly property real pausedMs: controller.pausedMs

  signal expired

  visible: !persistent
  height: hovered ? 3 : 2
  color: trackColor

  function start(startTime, alreadyPausedMs) {
    controller.start(startTime, alreadyPausedMs);
  }

  function restart(preserveHover) {
    controller.restart(preserveHover);
  }

  function pause() {
    controller.pause();
  }

  function resume() {
    controller.resume();
  }

  function stop() {
    controller.stop();
  }

  Behavior on height {
    MotionNumberAnimation { role: MotionNumberAnimation.Feedback }
  }

  Rectangle {
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: parent.width * controller.remainingProgress
    radius: parent.radius
    color: controller.hovered ? root.hoverAccentColor : root.accentColor

    Behavior on color {
      MotionColorAnimation { role: MotionNumberAnimation.Feedback }
    }
  }

  ToastLifetime {
    id: controller
    duration: root.duration
    persistent: root.persistent
    onExpired: root.expired()
  }
}
