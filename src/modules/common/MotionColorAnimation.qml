import QtQuick

ColorAnimation {
  id: root

  property int role: MotionNumberAnimation.Feedback

  readonly property Motion motion: Motion {}

  duration: {
    switch (role) {
    case MotionNumberAnimation.FocusTravel:
      return motion.focusTravelDuration;
    case MotionNumberAnimation.SurfaceEnter:
      return motion.surfaceEnterDuration;
    case MotionNumberAnimation.SurfaceExit:
      return motion.surfaceExitDuration;
    case MotionNumberAnimation.Content:
      return motion.contentDuration;
    case MotionNumberAnimation.Expressive:
      return motion.expressiveDuration;
    default:
      return motion.feedbackDuration;
    }
  }
  easing.type: Easing.BezierSpline
  easing.bezierCurve: {
    switch (role) {
    case MotionNumberAnimation.FocusTravel:
      return motion.focusTravelCurve;
    case MotionNumberAnimation.SurfaceEnter:
      return motion.surfaceEnterCurve;
    case MotionNumberAnimation.SurfaceExit:
      return motion.surfaceExitCurve;
    case MotionNumberAnimation.Content:
      return motion.contentCurve;
    case MotionNumberAnimation.Expressive:
      return motion.expressiveCurve;
    default:
      return motion.feedbackCurve;
    }
  }
}
