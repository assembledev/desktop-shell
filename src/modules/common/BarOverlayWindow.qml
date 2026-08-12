pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
  id: root

  required property var barSurface
  required property bool requested
  required property bool presented
  required property string surfaceNamespace
  property bool keyboardReady: false

  // This is an ordinary layer surface, not a pointer-grabbing popup. Its
  // geometry starts below the bar, so mapping and unmapping it never changes
  // pointer ownership for a stationary bar trigger.
  screen: root.barSurface?.screen
  visible: root.presented
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore

  WlrLayershell.namespace: root.surfaceNamespace
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: root.requested && root.keyboardReady
    ? WlrKeyboardFocus.OnDemand
    : WlrKeyboardFocus.None

  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }

  margins {
    top: Math.max(0, Number(root.barSurface?.height || 0))
  }

  // Hyprland retargets the pointer when a keyboard-interactive layer surface
  // maps, even if the cursor is outside that surface. Map keyboard-inert so a
  // stationary bar trigger keeps its pointer focus. Once the pointer actually
  // enters this surface, regular on-demand keyboard focus is safe to enable.
  HoverHandler {
    onHoveredChanged: {
      if (hovered)
        root.keyboardReady = true;
    }
  }

  onRequestedChanged: {
    if (!root.requested)
      root.keyboardReady = false;
  }

  onPresentedChanged: {
    if (!root.presented)
      root.keyboardReady = false;
  }
}
