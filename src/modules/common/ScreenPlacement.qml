import QtQuick

QtObject {
  id: root

  required property var configuration
  property string outputName: ""
  readonly property var screen: find(outputName)
  signal removed()

  function find(name) {
    return configuration.screens.find(candidate => String(candidate.name) === name) || null;
  }

  function target(preferred) {
    return find(String(preferred?.name || ""))
      || find(configuration.focusedOutputName)
      || find(configuration.outputName)
      || configuration.screens[0] || null;
  }

  function matches(preferred) {
    const next = target(preferred);
    return next !== null && next === screen;
  }

  function capture(preferred) {
    if (preferred !== undefined && !find(String(preferred?.name || ""))) {
      clear();
      return null;
    }
    outputName = String(target(preferred)?.name || "");
    return screen;
  }

  function clear() { outputName = ""; }

  onScreenChanged: {
    if (!screen && outputName.length > 0) {
      const missing = outputName;
      Qt.callLater(function() {
        if (root.outputName === missing && !root.screen) {
          root.clear();
          root.removed();
        }
      });
    }
  }
}
