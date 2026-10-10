pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

RowLayout {
  id: footer
  required property var colors
  required property var info
  implicitHeight: 16
  spacing: 10

  Text {
    Layout.fillWidth: true
    text: footer.info?.registrationTime > 0 ? Qt.formatDateTime(new Date(footer.info.registrationTime * 1000), "MMM dd HH:mm") : "Date unavailable"
    color: footer.colors.textMuted
    font.family: footer.colors.uiFontFamily
    font.pixelSize: 12
  }
  Text {
    text: footer.info?.state || ""
    color: footer.colors.textSecondary
    font.family: footer.colors.uiFontFamily
    font.pixelSize: 12
  }
}
