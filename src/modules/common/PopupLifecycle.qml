pragma ComponentBehavior: Bound

import Quickshell.Hyprland

HyprlandFocusGrab {
  id: root

  required property bool requested
  required property var surface
  property var companionSurfaces: []

  signal dismissed

  // The compositor consumes an outside press, clears the grab, then this
  // component returns that event to the popup's own state machine.
  // Companion surfaces remain interactive so their existing pointer cursors
  // and click handlers continue to work while the popup is open.
  windows: (root.surface ? [root.surface] : []).concat(root.companionSurfaces || [])
  active: root.requested && Boolean(root.surface?.backingWindowVisible)

  onCleared: {
    if (root.requested)
      root.dismissed();
  }
}
