import QtQuick

// Logical, output-local layout coordinates. Visual transforms deliberately do
// not participate: feedback and opening animations must not move the anchor.
QtObject {
  id: root
  property Item trigger: null
  property Item belowItem: null
  property real sourceTop: 0
  property real screenWidth: 0
  property real screenHeight: 0
  property real barHeight: 0
  property real surfaceTop: barHeight
  property real preferredWidth: 320
  property real edgeInset: 12
  property real gap: 2
  property bool active: false
  property bool hadAnchor: false
  readonly property bool validAnchor: trigger !== null && trigger.visible
  readonly property real width: Math.min(preferredWidth, Math.max(1, screenWidth - 2 * edgeInset))
  readonly property real center: trigger ? layoutPosition(trigger, "x") + trigger.width / 2 : screenWidth / 2
  readonly property real x: Math.max(edgeInset, Math.min(center - width / 2, screenWidth - width - edgeInset))
  readonly property real outputTop: (belowItem ? sourceTop + layoutPosition(belowItem, "y") + belowItem.height : barHeight) + gap
  readonly property real y: outputTop - surfaceTop
  readonly property real maximumHeight: Math.max(1, screenHeight - outputTop - edgeInset)
  signal anchorLost()

  // Reading every ancestor's layout properties installs real binding
  // dependencies; mapToItem() alone would leave a stale position after relayout.
  function layoutPosition(item, axis) {
    let position = 0;
    for (let current = item; current; current = current.parent)
      position += axis === "x" ? current.x : current.y;
    return position;
  }
  function checkAnchor() {
    if (active && hadAnchor && !validAnchor)
      Qt.callLater(function() {
        if (root.active && root.hadAnchor && !root.validAnchor)
          root.anchorLost();
      });
  }
  onActiveChanged: {
    hadAnchor = active && trigger !== null;
    checkAnchor();
  }
  onValidAnchorChanged: checkAnchor()
}
