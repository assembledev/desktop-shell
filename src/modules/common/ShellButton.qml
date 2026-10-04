import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "ShellSymbols.js" as Symbols

Button {
  id: button
  required property var colors
  property string label: ""
  property string glyph: ""
  property string imageSource: ""
  property string tooltip: ""
  property bool active: false
  property color accent: colors.accent
  property real maximumWidth: -1
  property bool flatAction: false
  readonly property bool iconOnly: label.length === 0
  text: label
  focusPolicy: Qt.StrongFocus
  hoverEnabled: true
  Accessible.role: Accessible.Button
  Accessible.name: label || tooltip || Symbols.name(glyph)
  Accessible.description: tooltip
  implicitHeight: 32
  implicitWidth: maximumWidth > 0 ? Math.min(maximumWidth, naturalWidth) : naturalWidth
  readonly property real naturalWidth: iconOnly ? 32 : Math.max(56, contentRow.implicitWidth + 20)
  horizontalPadding: iconOnly ? 6 : 10
  verticalPadding: 6
  contentItem: Item {
    implicitWidth: contentRow.implicitWidth
    implicitHeight: contentRow.implicitHeight
    RowLayout {
      id: contentRow
      anchors.centerIn: parent
      width: button.iconOnly ? implicitWidth : Math.min(implicitWidth, parent.width)
      spacing: 7
      ShellSymbol {
        visible: button.glyph.length > 0
        symbol: button.glyph
        size: 16
        tint: !button.enabled ? button.colors.textDisabled : button.active ? button.colors.textOnAccent : button.accent
        Layout.preferredWidth: 16
        Layout.preferredHeight: 16
        Layout.alignment: Qt.AlignVCenter
      }
      Image {
        visible: button.glyph.length === 0 && button.imageSource.length > 0
        source: visible ? button.imageSource : ""
        sourceSize.width: 16
        sourceSize.height: 16
        Layout.preferredWidth: 16
        Layout.preferredHeight: 16
        Layout.alignment: Qt.AlignVCenter
        fillMode: Image.PreserveAspectFit
      }
      Text {
        visible: !button.iconOnly
        Layout.fillWidth: true
        text: button.label
        color: !button.enabled ? button.colors.textDisabled : button.active ? button.colors.textOnAccent : button.flatAction ? button.accent : button.colors.textPrimary
        font.family: button.colors.uiFontFamily
        font.pixelSize: 12
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
      }
    }
  }
  background: Rectangle {
    radius: button.colors.controlRadius
    color: !button.enabled ? button.colors.bgMuted : button.active ? (button.down ? button.colors.accentHover : button.accent) : button.down || button.hovered ? button.colors.bgHover : button.flatAction ? "transparent" : button.colors.bgMuted
    Behavior on color {
      MotionColorAnimation {
        role: MotionNumberAnimation.Feedback
      }
    }
    Rectangle {
      anchors.fill: parent
      anchors.margins: -3
      radius: parent.radius + 3
      color: "transparent"
      border.color: button.colors.accent
      border.width: 2
      visible: button.visualFocus
    }
  }
  ToolTip {
    visible: button.hovered && button.tooltip.length > 0
    text: button.tooltip
    font.family: button.colors.uiFontFamily
    delay: 700
  }
}
