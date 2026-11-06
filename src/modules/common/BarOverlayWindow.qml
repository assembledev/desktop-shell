pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

PanelWindow {
  id: root

  required property var barSurface
  property var targetScreen: root.barSurface?.screen || null
  required property bool requested
  required property bool presented
  required property string surfaceNamespace
  property bool keyboardReady: false
  property bool keyboardRequested: false
  property Item popupContent: null
  property bool suspended: false
  property var allowedWindows: root.barSurface?.popupPeers || []
  readonly property bool nativeGrabActive: Boolean(grabLoader.item?.active)
  signal dismissRequested()

  // A grab is only requested after keyboard invocation or actual entry into
  // the card. Passive previews and stationary bar triggers keep their focus.
  Loader {
    id: grabLoader
    active: root.requested && !root.suspended && root.backingWindowVisible
      && root.popupContent !== null && (root.keyboardRequested || root.keyboardReady)
      && Boolean(Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE"))
    sourceComponent: HyprlandFocusGrab {
      id: grab
      active: true
      windows: [root]
      // Commit the card first so the compositor cannot select a bar as the
      // initial keyboard target. Broaden the allowlist on the next QML turn.
      onActiveChanged: if (active) Qt.callLater(function() {
        if (grab.active && root.requested && !root.suspended)
          grab.windows = Qt.binding(() => [root].concat(root.allowedWindows));
      })
      onCleared: if (root.requested && !root.suspended) root.dismissRequested()
    }
  }

  mask: Region {
    item: root.requested && !root.suspended
      ? (root.nativeGrabActive ? root.popupContent : root.contentItem) : null
  }

  // The layer starts below the bar so passive mapping cannot cover its
  // trigger. Keep it mapped but empty during an external chooser: returning
  // can restore the grab without racing Wayland surface recreation.
  screen: root.targetScreen
  visible: root.presented && root.targetScreen !== null
  contentItem.visible: !root.suspended
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore

  WlrLayershell.namespace: root.surfaceNamespace
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: !root.requested || root.suspended ? WlrKeyboardFocus.None
    : root.nativeGrabActive ? WlrKeyboardFocus.OnDemand
    : root.keyboardRequested ? WlrKeyboardFocus.Exclusive
    : root.keyboardReady ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

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
  // A caller opened by a keyboard command can explicitly acquire focus.
  HoverHandler {
    parent: root.popupContent || root.contentItem
    onHoveredChanged: {
      if (hovered && root.requested && !root.suspended)
        root.keyboardReady = true;
    }
  }

  onRequestedChanged: {
    if (!root.requested) {
      root.keyboardReady = false;
      root.keyboardRequested = false;
    }
  }

  onPresentedChanged: {
    if (!root.presented) {
      root.keyboardReady = false;
      root.keyboardRequested = false;
    }
  }
}
