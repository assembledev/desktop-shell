import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import "../common"

Item {
  id: network

  required property var controller
  property bool compactLabels: false
  property int targetHeight: 37
  required property int itemPadding
  required property int itemGap
  required property int contentGap
  readonly property var controls: controller.controls
  readonly property int textOpticalYOffset: 1
  readonly property real fullWidth: {
    let total = Math.max(0, providers.count - 1) * network.itemGap;
    for (let i = 0; i < providers.count; i++)
      total += providers.itemAt(i)?.fullWidth || 0;
    return total;
  }

  visible: controls.length > 0
  Layout.preferredWidth: visible ? content.implicitWidth : 0
  Layout.preferredHeight: targetHeight

  Theme { id: theme }
  function status(control) { return controller.status(control); }
  function activate(control) { controller.activate(control); }

  RowLayout {
    id: content
    anchors.centerIn: parent
    spacing: network.itemGap

    Repeater {
      id: providers
      model: network.controls

      delegate: RowLayout {
        required property int index
        required property var modelData

        readonly property real fullWidth: Math.ceil(18 + statusLabel.implicitWidth + 6
          + network.contentGap * 2 + network.itemPadding * 2)
          + (index < network.controls.length - 1 ? network.itemGap + 1 : 0)
        spacing: network.itemGap

        Item {
          id: statusItem
          property var currentStatus: network.status(modelData)
          readonly property bool active: Boolean(currentStatus.active)
          readonly property bool login: Boolean(currentStatus.login)
          readonly property bool busy: Boolean(currentStatus.busy)
          readonly property bool failed: String(currentStatus.error || "").length > 0

          Layout.preferredWidth: statusContent.implicitWidth + network.itemPadding * 2
          Layout.preferredHeight: network.targetHeight
          scale: itemMouse.pressed ? 0.94 : (itemMouse.containsMouse ? 1.025 : 1)

          Behavior on scale {
            MotionNumberAnimation { role: MotionNumberAnimation.Feedback }
          }

          Rectangle {
            anchors.centerIn: parent
            width: parent.width
            height: 24
            radius: 7
            color: statusItem.failed
              ? Qt.alpha(theme.danger, itemMouse.containsMouse ? 0.18 : 0.09)
              : (itemMouse.containsMouse ? theme.surfaceAccent : "transparent")

            Behavior on color {
              MotionColorAnimation { role: MotionNumberAnimation.Feedback }
            }
          }

          Row {
            id: statusContent
            anchors.centerIn: parent
            spacing: network.contentGap

            Image {
              width: 18
              height: 18
              anchors.verticalCenter: parent.verticalCenter
              source: modelData.icon || ""
              fillMode: Image.PreserveAspectFit
              sourceSize.width: Math.max(1, Math.ceil(width * Screen.devicePixelRatio))
              sourceSize.height: Math.max(1, Math.ceil(height * Screen.devicePixelRatio))
            }

            Text {
              id: statusLabel
              visible: !network.compactLabels
              anchors.verticalCenter: parent.verticalCenter
              anchors.verticalCenterOffset: network.textOpticalYOffset
              text: statusItem.failed
                ? ((modelData.label || statusItem.currentStatus.text || "Network") + " !")
                : (statusItem.currentStatus.text || modelData.label || "")
              color: statusItem.failed ? theme.danger : theme.textPrimary
              font.family: theme.uiFontFamily
              font.pixelSize: 15
              font.bold: true
            }

            Rectangle {
              width: 6
              height: 6
              radius: 3
              anchors.verticalCenter: parent.verticalCenter
              color: statusItem.failed ? theme.danger : statusItem.busy
                ? theme.warning
                : (statusItem.active ? theme.success : (statusItem.login ? theme.warning : theme.textMuted))
            }
          }

          MouseArea {
            id: itemMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: statusItem.busy ? Qt.BusyCursor : Qt.PointingHandCursor
            onClicked: network.activate(modelData)
          }
        }

        Rectangle {
          visible: index < network.controls.length - 1
          Layout.preferredWidth: visible ? 1 : 0
          Layout.preferredHeight: 14
          Layout.alignment: Qt.AlignVCenter
          color: Qt.alpha(theme.textMuted, 0.44)
          radius: 1
        }
      }
    }
  }
}
