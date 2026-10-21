import QtQuick
import Quickshell.Io

Item {
  id: network

  property string backend
  property string configPath
  property bool pollingEnabled: true
  property var controls: []
  property var statusById: ({})
  property int refreshNonce: 0
  signal statusRequested(string controlId)
  signal toggleRequested(string controlId)

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
    running: network.controls.length > 0 && network.pollingEnabled
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
        property bool reconcilingToggle: false
        property int transitionEpoch: 0
        property string statusOutput: ""
        property string statusError: ""
        property string toggleOutput: ""
        property string toggleError: ""

        function refresh() {
          if (!network.pollingEnabled || !modelData?.id)
            return;
          if (toggleProcess.running) {
            refreshPending = true;
            return;
          }
          if (statusProcess.running) {
            refreshPending = true;
            return;
          }

          refreshPending = false;
          statusOutput = "";
          statusError = "";
          statusProcess.epoch = transitionEpoch;
          statusProcess.exec([network.backend, "network-control", "status", modelData.id]);
        }

        function startToggle() {
          if (!modelData?.id || toggleProcess.running)
            return;

          // Status reads already in flight belong to the pre-toggle state and
          // must never finish the transition visually.
          transitionEpoch++;
          reconcilingToggle = false;
          refreshPending = false;
          toggleOutput = "";
          toggleError = "";
          toggleProcess.exec([network.backend, "network-control", "toggle", modelData.id]);
        }

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
          property int epoch: -1
          stdout: StdioCollector {
            onStreamFinished: poller.statusOutput = text
          }
          stderr: StdioCollector {
            onStreamFinished: poller.statusError = text
          }
          onExited: function(exitCode) {
            const current = statusProcess.epoch === poller.transitionEpoch;
            const completesToggle = current && poller.reconcilingToggle;

            if (!current) {
              // A status read may have started before or during the toggle.
              // Its result is stale even if the command itself succeeded.
            } else if (exitCode === 0) {
              const next = network.parseJson(poller.statusOutput, null);
              if (next && typeof next === "object") {
                network.setStatus(poller.modelData, Object.assign({}, next, {
                  busy: completesToggle ? false : network.status(poller.modelData).busy,
                  error: "",
                  errorKind: ""
                }));
              } else {
                network.setStatus(poller.modelData, {
                  busy: completesToggle ? false : network.status(poller.modelData).busy,
                  error: "Status command returned invalid JSON",
                  errorKind: "status"
                });
                console.error("network control " + poller.modelData.id + " status returned invalid JSON");
              }
            } else {
              network.setStatus(poller.modelData, {
                busy: completesToggle ? false : network.status(poller.modelData).busy,
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

            if (completesToggle)
              poller.reconcilingToggle = false;

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
              // Keep the yellow transition state until a status read started
              // after this command confirms the new provider state.
              poller.transitionEpoch++;
              poller.reconcilingToggle = true;
              poller.refreshPending = false;
              network.setStatus(poller.modelData, {
                busy: true,
                error: "",
                errorKind: ""
              });
              Qt.callLater(function() { poller.refresh(); });
            } else {
              poller.transitionEpoch++;
              poller.reconcilingToggle = false;
              poller.refreshPending = false;
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

}
