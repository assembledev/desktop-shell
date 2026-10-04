import QtQuick
import QtQuick.Controls
import "../common"

ShellTaskButton {
  id: row
  property bool toggleEnabled: true
  signal toggleRequested
  signal detailRequested
  accent: colors.info
  implicitHeight: 54
  showGlyph: false
  navigation: true
  cornerRadius: colors.groupRadius
  leftPadding: 54
  rightPadding: 12
  onClicked: detailRequested()
  Button {
    id: radio
    parent: row
    x: 12
    anchors.verticalCenter: parent.verticalCenter
    width: 32
    height: 32
    padding: 6
    focusPolicy: Qt.StrongFocus
    hoverEnabled: true
    enabled: row.toggleEnabled
    Accessible.name: (row.active ? "Turn off " : "Turn on ") + row.title
    onClicked: row.toggleRequested()
    contentItem: ShellSymbol {
      symbol: row.glyph
      tint: row.active ? row.colors.textOnAccent : row.colors.textPrimary
      size: 20
    }
    background: Rectangle {
      radius: width / 2
      color: radio.down ? row.colors.accentHover : row.active ? row.accent : radio.hovered ? row.colors.bgHover : row.colors.bgMuted
      opacity: radio.enabled ? 1 : .5
      Rectangle {
        anchors.fill: parent
        anchors.margins: -3
        radius: width / 2
        color: "transparent"
        border.color: row.colors.accent
        border.width: 2
        visible: radio.visualFocus
      }
    }
  }
}
