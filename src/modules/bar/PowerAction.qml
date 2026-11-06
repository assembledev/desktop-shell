import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../common"

Button {
  id: action
  required property var colors
  property string iconText
  property string label
  property color accent: action.colors.accent
  property bool danger: false

  Layout.fillWidth: true
  Layout.preferredHeight: 42
  focusPolicy: Qt.StrongFocus
  hoverEnabled: true
  padding: 0
  Accessible.name: label
  Accessible.role: Accessible.Button
  Keys.onReturnPressed: click()
  Keys.onEnterPressed: click()
  scale: down ? 0.97 : 1

  background: Rectangle {
    radius: 9
    color: action.hovered || action.visualFocus ? (action.danger ? Qt.alpha(action.colors.danger, 0.14) : action.colors.surfaceAccent) : "transparent"
    border.color: action.visualFocus ? action.colors.accent : "transparent"
    border.width: action.visualFocus ? 2 : 0
    Behavior on color {
      MotionColorAnimation { role: MotionNumberAnimation.Feedback }
    }
  }

  Behavior on scale {
    MotionNumberAnimation {
      role: MotionNumberAnimation.Feedback
    }
  }

  contentItem: RowLayout {
    anchors.fill: parent
    anchors.leftMargin: 8
    anchors.rightMargin: 8
    spacing: 10

    Rectangle {
      Layout.preferredWidth: 28
      Layout.preferredHeight: 28
      radius: 8
      color: Qt.alpha(action.accent, action.hovered || action.visualFocus ? 0.25 : 0.15)

      Behavior on color {
        MotionColorAnimation {
          role: MotionNumberAnimation.Feedback
        }
      }

      Text {
        anchors.centerIn: parent
        text: action.iconText
        color: action.accent
        font.family: action.colors.fontFamily
        font.pixelSize: 14
        font.bold: true
      }
    }

    Text {
      text: action.label
      color: action.colors.textPrimary
      font.family: action.colors.uiFontFamily
      font.pixelSize: 13
      font.bold: true
      Layout.fillWidth: true
      elide: Text.ElideRight
    }
  }

  HoverHandler { cursorShape: action.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
}
