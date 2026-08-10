pragma ComponentBehavior: Bound

import Quickshell.Hyprland

HyprlandFocusGrab {
  id: root

  required property bool requested
  required property var surface

  signal dismissed

  // The compositor consumes an outside press, clears the grab, then this
  // component returns that event to the popup's own state machine.
  windows: root.surface ? [root.surface] : []
  active: root.requested && Boolean(root.surface?.backingWindowVisible)

  onCleared: {
    if (root.requested)
      root.dismissed();
  }
}
