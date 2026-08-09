import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../common"

Item {
  id: network

  property string backend
  property string configPath
  property bool compact: false
  property bool pollingEnabled: true
  property int targetHeight: 37
  property var controls: []
  property var statusById: ({})
  property int refreshNonce: 0

  readonly property int textOpticalYOffset: 1

  visible: controls.length > 0
  Layout.preferredWidth: visible ? content.implicitWidth : 0
  Layout.preferredHeight: targetHeight
  Layout.rightMargin: visible ? (compact ? 5 : 12) : 0

  Theme {
    id: theme
  }

  function parseJson(text, fallback) {
    const raw = String(text || "").trim();
    if (!raw)
      return fallback;

    try {
      return JSON.parse(raw);
    } catch (error) {
      console.error("network controls: JSON parse failed: " + error);
      return fallback;
    }
  }

  function loadControls() {
    const config = parseJson(configFile.text(), {});
    const nextControls = Array.isArray(config)
      ? config
      : (config?.bar?.networkControls || []);
    const nextStatus = {};

    for (const control of nextControls) {
      if (!control.id)
        continue;

      nextStatus[control.id] = statusById[control.id] || defaultStatus(control);
    }

    controls = nextControls;
    statusById = nextStatus;
    refreshNonce++;
  }

  function defaultStatus(control) {
    return {
      text: control?.label || "",
      active: false,
      login: false,
    };
  }

  function status(control) {
    return Object.assign(defaultStatus(control), statusById[control?.id] || {});
  }

  function setStatus(control, next) {
    if (!control?.id)
      return;

    const statuses = Object.assign({}, statusById);
    statuses[control.id] = Object.assign(defaultStatus(control), next || {});
    statusById = statuses;
  }

  function toggle(control) {
    if (control?.id)
      toggleProcess.exec([backend, "network-control", "toggle", control.id]);
  }

  onPollingEnabledChanged: {
    if (pollingEnabled)
      refreshNonce++;
  }

  Timer {
    interval: 60000
    running: network.visible && network.pollingEnabled
    repeat: true
    onTriggered: network.refreshNonce++
  }

  FileView {
    id: configFile
    path: network.configPath
    preload: true
    watchChanges: true
    onFileChanged: reload()
    onLoaded: network.loadControls()
    onTextChanged: network.loadControls()
    onLoadFailed: function() {
      network.controls = [];
      network.statusById = ({});
    }
  }

  Process {
    id: toggleProcess
    onExited: network.refreshNonce++
  }

  Item {
    visible: false

    Repeater {
      model: network.controls

      delegate: Item {
        id: poller
        required property var modelData

        function refresh() {
          if (network.pollingEnabled && modelData?.id)
            statusProcess.exec([network.backend, "network-control", "status", modelData.id]);
        }

        onModelDataChanged: refresh()
        Component.onCompleted: refresh()

        Connections {
          target: network
          function onRefreshNonceChanged() { poller.refresh(); }
        }

        Process {
          id: statusProcess
          stdout: StdioCollector {
            onStreamFinished: network.setStatus(
              poller.modelData,
              network.parseJson(text, network.status(poller.modelData))
            )
          }
        }
      }
    }
  }

  RowLayout {
    id: content
    anchors.centerIn: parent
    spacing: network.compact ? 4 : 6

    Repeater {
      model: network.controls

      delegate: RowLayout {
        required property int index
        required property var modelData

        spacing: network.compact ? 4 : 6

        Item {
          id: statusItem
          property var currentStatus: network.status(modelData)
          readonly property bool active: Boolean(currentStatus.active)
          readonly property bool login: Boolean(currentStatus.login)

          Layout.preferredWidth: statusContent.implicitWidth + 10
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
            color: itemMouse.containsMouse ? theme.surfaceAccent : "transparent"

            Behavior on color {
              MotionColorAnimation { role: MotionNumberAnimation.Feedback }
            }
          }

          Row {
            id: statusContent
            anchors.centerIn: parent
            spacing: 6

            Image {
              width: 18
              height: 18
              anchors.verticalCenter: parent.verticalCenter
              source: modelData.icon || ""
              fillMode: Image.PreserveAspectFit
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              anchors.verticalCenterOffset: network.textOpticalYOffset
              text: statusItem.currentStatus.text || modelData.label || ""
              color: theme.text
              font.family: theme.fontFamily
              font.pixelSize: 15
              font.bold: true
            }

            Rectangle {
              width: 6
              height: 6
              radius: 3
              anchors.verticalCenter: parent.verticalCenter
              color: statusItem.active ? theme.green : (statusItem.login ? theme.yellow : theme.red)
            }
          }

          MouseArea {
            id: itemMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: network.toggle(modelData)
          }
        }

        Rectangle {
          visible: index < network.controls.length - 1
          Layout.preferredWidth: visible ? 1 : 0
          Layout.preferredHeight: 14
          Layout.alignment: Qt.AlignVCenter
          color: Qt.alpha(theme.mutedAlt, 0.44)
          radius: 1
        }
      }
    }
  }
}
