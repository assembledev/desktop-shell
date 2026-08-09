import QtQuick

NumberAnimation {
  id: root

  enum Role {
    Feedback,
    FocusTravel,
    SurfaceEnter,
    SurfaceExit,
    Content,
    Expressive
  }

  property int role: MotionNumberAnimation.FocusTravel
  property real speedMultiplier: 1

  readonly property Motion motion: Motion {}

  readonly property int baseDuration: {
    switch (role) {
    case MotionNumberAnimation.Feedback:
      return motion.feedbackDuration;
    case MotionNumberAnimation.SurfaceEnter:
      return motion.surfaceEnterDuration;
    case MotionNumberAnimation.SurfaceExit:
      return motion.surfaceExitDuration;
    case MotionNumberAnimation.Content:
      return motion.contentDuration;
    case MotionNumberAnimation.Expressive:
      return motion.expressiveDuration;
    default:
      return motion.focusTravelDuration;
    }
  }
  duration: Math.max(1, Math.round(baseDuration / Math.max(0.01, speedMultiplier)))
  easing.type: Easing.BezierSpline
  easing.bezierCurve: {
    switch (role) {
    case MotionNumberAnimation.Feedback:
      return motion.feedbackCurve;
    case MotionNumberAnimation.SurfaceEnter:
      return motion.surfaceEnterCurve;
    case MotionNumberAnimation.SurfaceExit:
      return motion.surfaceExitCurve;
    case MotionNumberAnimation.Content:
      return motion.contentCurve;
    case MotionNumberAnimation.Expressive:
      return motion.expressiveCurve;
    default:
      return motion.focusTravelCurve;
    }
  }
}
