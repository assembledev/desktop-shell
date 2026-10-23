import QtQuick
import QtQuick.Controls

ToolTip {
  id: tip
  required property var colors

  font.family: colors.uiFontFamily
  font.pixelSize: 11

  contentItem: Text {
    text: tip.text
    textFormat: Text.PlainText
    font: tip.font
    color: tip.colors.textPrimary
    wrapMode: Text.Wrap
  }

  background: Rectangle {
    radius: tip.colors.controlRadius
    color: tip.colors.bgToast
    border.color: tip.colors.borderMuted
    border.width: 1
  }
}
