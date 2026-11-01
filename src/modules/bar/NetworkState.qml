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
  signal selectionRequested(string controlId, string profileId)

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

  function profiles(control) {
    // Delegates can expose nested arrays as list models. Resolve capability
    // from the configuration owned here, using the provider's identity.
    const configured = controls.find(item => item.id === control?.id);
    if (!Array.isArray(configured?.selectCommand) || configured.selectCommand.length === 0)
      return [];
    const choices = status(control).profiles;
    const ids = new Set();
    if (!Array.isArray(choices) || !choices.every(profile => {
      if (!profile || typeof profile.id !== "string" || !/^[A-Za-z0-9_.-]+$/.test(profile.id)
          || typeof profile.label !== "string" || !profile.label.length || ids.has(profile.id))
        return false;
      ids.add(profile.id);
      return true;
    })) return [];
    return choices;
  }

  function selectProfile(control, profileId) {
    if (!control?.id || status(control).busy || !profiles(control).some(profile => profile.id === profileId))
      return;
    setStatus(control, { busy: true, error: "", errorKind: "" });
    selectionRequested(control.id, profileId);
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
        property bool reconcilingAction: false
        property int transitionEpoch: 0
        property string statusOutput: ""
        property string statusError: ""
        property string actionOutput: ""
        property string actionError: ""
        property string actionName: ""
        property string actionFailure: ""

        function refresh() {
          if ((!network.pollingEnabled && !reconcilingAction) || !modelData?.id)
            return;
          if (actionProcess.running) {
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

        function startAction(action, profileId) {
          if (!modelData?.id || actionProcess.running)
            return;

          // Status reads already in flight belong to the previous state and
          // must never finish the transition visually.
          transitionEpoch++;
          reconcilingAction = false;
          refreshPending = false;
          actionOutput = "";
          actionError = "";
          actionFailure = "";
          actionName = action;
          const command = [network.backend, "network-control", action, modelData.id];
          if (action === "select") command.push(profileId);
          actionProcess.exec(command);
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
              poller.startAction("toggle");
          }
          function onSelectionRequested(controlId, profileId) {
            if (controlId === poller.modelData?.id)
              poller.startAction("select", profileId);
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
            const completesAction = current && poller.reconcilingAction;

            if (!current) {
              // A status read may have started before or during the toggle.
              // Its result is stale even if the command itself succeeded.
            } else if (exitCode === 0) {
              const next = network.parseJson(poller.statusOutput, null);
              if (next && typeof next === "object") {
                network.setStatus(poller.modelData, Object.assign({}, next, {
                  busy: completesAction ? false : network.status(poller.modelData).busy,
                  error: poller.actionFailure,
                  errorKind: poller.actionFailure ? poller.actionName : ""
                }));
              } else {
                network.setStatus(poller.modelData, {
                  busy: completesAction ? false : network.status(poller.modelData).busy,
                  error: poller.actionFailure || "Status command returned invalid JSON",
                  errorKind: "status"
                });
                console.error("network control " + poller.modelData.id + " status returned invalid JSON");
              }
            } else {
              network.setStatus(poller.modelData, {
                busy: completesAction ? false : network.status(poller.modelData).busy,
                error: poller.actionFailure || network.commandError(
                  poller.modelData,
                  "status",
                  exitCode,
                  poller.statusError,
                  poller.statusOutput
                ),
                errorKind: "status"
              });
            }

            if (completesAction)
              poller.reconcilingAction = false;

            if (poller.refreshPending)
              Qt.callLater(function() { poller.refresh(); });
          }
        }

        Process {
          id: actionProcess
          stdout: StdioCollector {
            onStreamFinished: poller.actionOutput = text
          }
          stderr: StdioCollector {
            onStreamFinished: poller.actionError = text
          }
          onExited: function(exitCode) {
            // Failed selections may still change the requested profile. Always
            // reconcile provider state, retaining the command's useful error.
            poller.actionFailure = exitCode === 0 ? "" : network.commandError(
              poller.modelData, poller.actionName, exitCode, poller.actionError, poller.actionOutput);
            poller.transitionEpoch++;
            poller.reconcilingAction = true;
            poller.refreshPending = false;
            network.setStatus(poller.modelData, { busy: true,
              error: poller.actionFailure, errorKind: poller.actionFailure ? poller.actionName : "" });
            Qt.callLater(function() { poller.refresh(); });
          }
        }
      }
    }
  }

}
