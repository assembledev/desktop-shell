pragma ComponentBehavior: Bound

import QtQuick

Item {
  id: root

  // Delegate hover transitions also fire when scrolling moves content beneath
  // a stationary cursor. Scene movement on the fixed surface is real intent.
  property Item surface: parent
  property bool pointerActive: false
  property bool hasPointerPosition: false
  property point lastPointerScenePosition: Qt.point(0, 0)
  property point latestPointerScenePosition: Qt.point(0, 0)
  property real movementThreshold: 0.5

  signal pointerActivity()

  function claimKeyboard() {
    pointerActive = false;
    lastPointerScenePosition = latestPointerScenePosition;
  }

  function claimPointer() {
    pointerActive = true;
    pointerActivity();
  }

  function observePointerScenePosition(position) {
    const next = Qt.point(Number(position.x), Number(position.y));
    latestPointerScenePosition = next;
    if (!hasPointerPosition) {
      lastPointerScenePosition = next;
      hasPointerPosition = true;
      return;
    }

    const moved = Math.abs(next.x - lastPointerScenePosition.x) > movementThreshold
      || Math.abs(next.y - lastPointerScenePosition.y) > movementThreshold;
    // Measure displacement from the last accepted sample, not each tiny
    // event. Slow movement accumulates; back-and-forth jitter does not.
    if (moved) {
      lastPointerScenePosition = next;
      claimPointer();
    }
  }

  HoverHandler {
    parent: root.surface
    blocking: false
    onPointChanged: root.observePointerScenePosition(point.scenePosition)
  }

  WheelHandler {
    parent: root.surface
    blocking: false
    onWheel: root.claimPointer()
  }
}
