import QtQuick

Rectangle {
  required property var colors
  radius: colors.groupRadius
  color: colors.surfaceRaised
  border.color: colors.borderMuted
  border.width: 1
}
