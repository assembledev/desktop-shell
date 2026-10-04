import QtQuick
import QtQuick.Controls

Slider {
  id: control
  required property var colors
  property color accent: colors.accent
  property bool boostAllowed: false
  property bool dimmed: false
  readonly property real unityPosition: Math.max(0, Math.min(1, (1 - from) / Math.max(.001, to - from)))
  implicitHeight: 28
  focusPolicy: Qt.StrongFocus
  opacity: enabled ? 1 : .5
  background: Rectangle {
    x: control.leftPadding + 9
    y: control.topPadding + control.availableHeight / 2 - 4
    width: Math.max(0, control.availableWidth - 18)
    height: 8
    radius: 4
    color: control.colors.border
    Rectangle {
      width: parent.width * control.visualPosition
      height: parent.height
      radius: parent.radius
      color: control.dimmed ? control.colors.textDisabled : control.colors.textMuted
    }
    Rectangle {
      visible: control.boostAllowed && control.visualPosition > control.unityPosition
      x: parent.width * control.unityPosition
      width: Math.max(0, parent.width * (control.visualPosition - control.unityPosition))
      height: parent.height
      radius: parent.radius
      color: control.colors.caution
    }
    Rectangle {
      visible: control.boostAllowed
      x: parent.width * control.unityPosition - 1
      width: 2
      height: 8
      color: control.colors.textSecondary
    }
  }
  handle: Rectangle {
    x: control.leftPadding + control.visualPosition * (control.availableWidth - width)
    y: control.topPadding + control.availableHeight / 2 - height / 2
    implicitWidth: 18
    implicitHeight: 18
    radius: 9
    color: control.colors.textPrimary
    border.color: control.visualFocus ? control.accent : control.colors.textMuted
    border.width: control.visualFocus ? 2 : 1
  }
}
