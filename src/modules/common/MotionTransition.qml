import QtQuick

QtObject {
  id: root

  property bool requested: false
  property bool presented: false
  property real progress: 0
  property bool animationEnabled: true
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
      presented = true;
      progress = 1;
    } else {
      progress = 0;
      if (!progressAnimation.running)
        finishDismiss();
    }
  }

  Component.onCompleted: {
    if (requested) {
      presented = true;
      progress = 1;
    }
  }

  Behavior on progress {
    enabled: root.animationEnabled
    MotionNumberAnimation {
      id: progressAnimation
      role: root.requested
        ? MotionNumberAnimation.SurfaceEnter
        : MotionNumberAnimation.SurfaceExit
      onRunningChanged: {
        if (!running)
          root.finishDismiss();
      }
    }
  }
}
