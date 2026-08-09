import QtQuick

QtObject {
  // Fast interaction feedback should feel immediate. Spatial motion gets more
  // time because the eye needs to track where an object went, while exits are
  // deliberately shorter than entrances.
  readonly property int feedbackDuration: 120
  readonly property int focusTravelDuration: 220
  readonly property int surfaceEnterDuration: 300
  readonly property int surfaceExitDuration: 200
  readonly property int contentDuration: 250
  readonly property int expressiveDuration: 380

  readonly property var feedbackCurve: [0.2, 0, 0, 1, 1, 1]
  readonly property var focusTravelCurve: [0.2, 0.78, 0.2, 1, 1, 1]
  readonly property var surfaceEnterCurve: [0.16, 0.92, 0.24, 1, 1, 1]
  readonly property var surfaceExitCurve: [0.4, 0, 0.8, 0.2, 1, 1]
  readonly property var contentCurve: [0.2, 0.72, 0.2, 1, 1, 1]
  readonly property var expressiveCurve: [0.34, 1.28, 0.28, 1, 1, 1]
}
