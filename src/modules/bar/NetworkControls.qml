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
  signal statusRequested(string controlId)
  signal toggleRequested(string controlId)

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

      nextStatus[control.id] = Object.assign(
        defaultStatus(control),
        statusById[control.id] || {},
        { busy: false }
      );
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
      busy: false,
      error: "",
      errorKind: "",
    };
  }

  function status(control) {
    return Object.assign(defaultStatus(control), statusById[control?.id] || {});
  }

  function setStatus(control, next) {
    if (!control?.id)
      return;

    const statuses = Object.assign({}, statusById);
    statuses[control.id] = Object.assign(
      defaultStatus(control),
      statuses[control.id] || {},
      next || {}
    );
    statusById = statuses;
  }

  function commandError(control, action, exitCode, stderr, stdout) {
    const details = String(stderr || stdout || "").trim();
    const message = details || (action + " command exited with status " + exitCode);
    console.error("network control " + control.id + " " + action + " failed: " + message);
    return message;
  }

  function activate(control) {
    if (!control?.id)
      return;

    const current = status(control);
    if (current.busy)
      return;

    if (current.errorKind === "status") {
      setStatus(control, { error: "", errorKind: "" });
      statusRequested(control.id);
      return;
    }

    setStatus(control, { busy: true, error: "", errorKind: "" });
    toggleRequested(control.id);
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

  Item {
    visible: false

    Repeater {
      model: network.controls

      delegate: Item {
        id: poller
        required property var modelData
        property bool refreshPending: false
        property string statusOutput: ""
        property string statusError: ""
        property string toggleOutput: ""
        property string toggleError: ""

        function refresh() {
          if (!network.pollingEnabled || !modelData?.id)
            return;
          if (statusProcess.running) {
            refreshPending = true;
            return;
          }

          refreshPending = false;
          statusOutput = "";
          statusError = "";
          statusProcess.exec([network.backend, "network-control", "status", modelData.id]);
        }

        function startToggle() {
          if (!modelData?.id || toggleProcess.running)
            return;

          toggleOutput = "";
          toggleError = "";
          toggleProcess.exec([network.backend, "network-control", "toggle", modelData.id]);
        }

        onModelDataChanged: refresh()
        Component.onCompleted: refresh()

        Connections {
          target: network
          function onRefreshNonceChanged() { poller.refresh(); }
          function onStatusRequested(controlId) {
            if (controlId === poller.modelData?.id)
              poller.refresh();
          }
          function onToggleRequested(controlId) {
            if (controlId === poller.modelData?.id)
              poller.startToggle();
          }
        }

        Process {
          id: statusProcess
          stdout: StdioCollector {
            onStreamFinished: poller.statusOutput = text
          }
          stderr: StdioCollector {
            onStreamFinished: poller.statusError = text
          }
          onExited: function(exitCode) {
            if (exitCode === 0) {
              const next = network.parseJson(poller.statusOutput, null);
              if (next && typeof next === "object") {
                network.setStatus(poller.modelData, Object.assign({}, next, {
                  error: "",
                  errorKind: ""
                }));
              } else {
                network.setStatus(poller.modelData, {
                  error: "Status command returned invalid JSON",
                  errorKind: "status"
                });
                console.error("network control " + poller.modelData.id + " status returned invalid JSON");
              }
            } else {
              network.setStatus(poller.modelData, {
                error: network.commandError(
                  poller.modelData,
                  "status",
                  exitCode,
                  poller.statusError,
                  poller.statusOutput
                ),
                errorKind: "status"
              });
            }

            if (poller.refreshPending)
              Qt.callLater(function() { poller.refresh(); });
          }
        }

        Process {
          id: toggleProcess
          stdout: StdioCollector {
            onStreamFinished: poller.toggleOutput = text
          }
          stderr: StdioCollector {
            onStreamFinished: poller.toggleError = text
          }
          onExited: function(exitCode) {
            if (exitCode === 0) {
              network.setStatus(poller.modelData, {
                busy: false,
                error: "",
                errorKind: ""
              });
              poller.refresh();
            } else {
              network.setStatus(poller.modelData, {
                busy: false,
                error: network.commandError(
                  poller.modelData,
                  "toggle",
                  exitCode,
                  poller.toggleError,
                  poller.toggleOutput
                ),
                errorKind: "toggle"
              });
            }
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
          readonly property bool busy: Boolean(currentStatus.busy)
          readonly property bool failed: String(currentStatus.error || "").length > 0

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
            color: statusItem.failed
              ? Qt.alpha(theme.red, itemMouse.containsMouse ? 0.18 : 0.09)
              : (itemMouse.containsMouse ? theme.surfaceAccent : "transparent")

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
              text: statusItem.failed
                ? ((modelData.label || statusItem.currentStatus.text || "Network") + " !")
                : (statusItem.currentStatus.text || modelData.label || "")
              color: statusItem.failed ? theme.red : theme.text
              font.family: theme.fontFamily
              font.pixelSize: 15
              font.bold: true
            }

            Rectangle {
              width: 6
              height: 6
              radius: 3
              anchors.verticalCenter: parent.verticalCenter
              color: statusItem.busy
                ? theme.yellow
                : (statusItem.active ? theme.green : (statusItem.login ? theme.yellow : theme.red))
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
          color: Qt.alpha(theme.mutedAlt, 0.44)
          radius: 1
        }
      }
    }
  }
}
