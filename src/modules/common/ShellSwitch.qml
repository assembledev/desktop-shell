import QtQuick
import QtQuick.Controls

Switch {
  id: control
  required property var colors
  property bool busy: false
  property color accent: colors.accent
  Accessible.role: Accessible.CheckBox
  Accessible.checked: checked
  focusPolicy: Qt.StrongFocus
  hoverEnabled: true
  implicitWidth: 42
  implicitHeight: 32
  padding: 0
  indicator: Rectangle {
    width: 36
    height: 22
    x: (control.width - width) / 2
    y: (control.height - height) / 2
    radius: 11
    color: control.checked ? control.accent : control.colors.border
    opacity: control.enabled ? 1 : .5
    Rectangle {
      width: 18
      height: 18
      radius: 9
      x: control.checked ? 16 : 2
      y: 2
      color: control.colors.textPrimary
      opacity: control.busy ? .6 : 1
    }
    Rectangle {
      anchors.fill: parent
      anchors.margins: -3
      color: "transparent"
      radius: 14
      border.color: control.colors.accent
      border.width: 2
      visible: control.visualFocus
    }
  }
  contentItem: Item {}
}
