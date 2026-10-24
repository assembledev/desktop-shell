import QtQuick
import "../common"

Column {
  spacing: 10

  move: Transition {
    MotionNumberAnimation {
      properties: "y"
      role: MotionNumberAnimation.FocusTravel
    }
  }
}
