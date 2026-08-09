import QtQuick

QtObject {
  id: root

  property bool requested: false
  property bool presented: false
  property real progress: 0
  property bool animationEnabled: true
  property real enterSpeedMultiplier: 1
  property real exitSpeedMultiplier: 1
  property int activeRole: MotionNumberAnimation.SurfaceExit
  property real activeSpeedMultiplier: 1
  readonly property bool running: progressAnimation.running

  signal dismissed

  function finishDismiss() {
    if (requested || progress > 0.001 || !presented)
      return;
    presented = false;
    dismissed();
  }

  function snapDismissed() {
    progressAnimation.stop();
    animationEnabled = false;
    progress = 0;
    presented = false;
    animationEnabled = true;
  }

  onRequestedChanged: {
    if (requested) {
      activeRole = MotionNumberAnimation.SurfaceEnter;
      activeSpeedMultiplier = enterSpeedMultiplier;
      presented = true;
      progress = 1;
    } else {
      activeRole = MotionNumberAnimation.SurfaceExit;
      activeSpeedMultiplier = exitSpeedMultiplier;
      progress = 0;
      if (!progressAnimation.running)
        finishDismiss();
    }
  }

  Component.onCompleted: {
    if (requested) {
      activeRole = MotionNumberAnimation.SurfaceEnter;
      activeSpeedMultiplier = enterSpeedMultiplier;
      presented = true;
      progress = 1;
    }
  }

  Behavior on progress {
    enabled: root.animationEnabled
    MotionNumberAnimation {
      id: progressAnimation
      role: root.activeRole
      speedMultiplier: root.activeSpeedMultiplier
      onRunningChanged: {
        if (!running)
          root.finishDismiss();
      }
    }
  }
}
