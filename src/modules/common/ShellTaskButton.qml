import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Button {
  id: task
  required property var colors
  property string title: ""
  property string subtitle: ""
  property string glyph: ""
  property bool showGlyph: true
  property bool active: false
  property bool navigation: false
  property bool surface: false
  property real cornerRadius: colors.controlRadius
  property bool roundedTop: true
  property bool roundedBottom: true
  property color accent: colors.accent
  implicitHeight: subtitle.length > 0 ? 50 : 34
  horizontalPadding: 12
  verticalPadding: 6
  focusPolicy: Qt.StrongFocus
  hoverEnabled: true
  Accessible.role: checkable ? Accessible.CheckBox : Accessible.Button
  Accessible.checked: checked
  Accessible.name: title + (subtitle ? ", " + subtitle : "")
  contentItem: RowLayout {
    spacing: 10
    ShellSymbol {
      visible: task.showGlyph && task.glyph.length > 0
      symbol: task.glyph
      tint: task.active ? task.accent : task.colors.textPrimary
      size: 24
      Layout.preferredWidth: 24
      Layout.preferredHeight: 24
      Layout.alignment: Qt.AlignVCenter
    }
    ColumnLayout {
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignVCenter
      spacing: 2
      Text {
        Layout.fillWidth: true
        text: task.title
        color: task.colors.textPrimary
        font.family: task.colors.uiFontFamily
        font.pixelSize: 12
        font.bold: true
        elide: Text.ElideRight
        verticalAlignment: Text.AlignVCenter
      }
      Text {
        visible: task.subtitle.length > 0
        Layout.fillWidth: true
        text: task.subtitle
        color: task.colors.textSecondary
        font.family: task.colors.uiFontFamily
        font.pixelSize: 10
        elide: Text.ElideRight
      }
    }
    ShellSymbol {
      visible: task.navigation
      symbol: "right"
      size: 12
      tint: task.colors.textMuted
      Layout.preferredWidth: 12
      Layout.preferredHeight: 12
      Layout.alignment: Qt.AlignVCenter
    }
  }
  HoverHandler {
    id: wholeButtonHover
  }
  background: Rectangle {
    topLeftRadius: task.roundedTop ? task.cornerRadius : 0
    topRightRadius: task.roundedTop ? task.cornerRadius : 0
    bottomLeftRadius: task.roundedBottom ? task.cornerRadius : 0
    bottomRightRadius: task.roundedBottom ? task.cornerRadius : 0
    color: !task.enabled ? (task.surface ? task.colors.surfaceRaised : "transparent") : task.down || wholeButtonHover.hovered ? task.colors.surfaceHover : task.surface ? task.colors.surfaceRaised : "transparent"
    border.color: task.visualFocus ? task.colors.accent : task.colors.borderMuted
    border.width: task.visualFocus ? 2 : task.surface ? 1 : 0
    Behavior on color {
      MotionColorAnimation {
        role: MotionNumberAnimation.Feedback
      }
    }
  }
}
