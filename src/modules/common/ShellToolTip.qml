pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

PopupWindow {
  id: root

  required property Item anchorItem
  property string text: ""
  property bool shown: false
  property int delay: 450
  property int maximumTextWidth: 300
  property bool ready: false
  readonly property int edgePadding: 8
  readonly property int horizontalPadding: 10
  readonly property int verticalPadding: 7
  readonly property real availableTextWidth: {
    const screenWidth = Number(root.screen?.width || 0);
    return screenWidth > 0
      ? Math.max(1, Math.min(root.maximumTextWidth, screenWidth - 2 * root.edgePadding - 24))
      : root.maximumTextWidth;
  }
  readonly property bool requested: root.shown && root.text.trim().length > 0

  visible: root.ready && root.requested
  implicitWidth: Math.ceil(tipText.width) + 2 * (root.horizontalPadding + root.edgePadding)
  implicitHeight: Math.ceil(tipText.implicitHeight) + 2 * (root.verticalPadding + root.edgePadding)
  color: "transparent"
  grabFocus: false

  anchor.item: root.anchorItem
  // Quickshell's qmltypes exposes these flag properties without their enum
  // types, even though they are part of PopupAnchor's public QML API.
  // qmllint disable missing-type
  anchor.edges: Edges.Top
  anchor.gravity: Edges.Top
  anchor.adjustment: PopupAdjustment.All
  // qmllint enable missing-type

  Theme {
    id: theme
  }

  TextMetrics {
    id: tipMetrics
    font.family: theme.fontFamily
    font.pixelSize: 10
    text: root.text
  }

  Rectangle {
    anchors.fill: parent
    anchors.margins: root.edgePadding
    radius: 7
    color: theme.surfaceToast
    border.color: theme.borderMuted
    border.width: 1

    Text {
      id: tipText
      anchors.centerIn: parent
      width: Math.min(tipMetrics.advanceWidth, root.availableTextWidth)
      text: root.text
      color: theme.textPrimary
      font.family: theme.fontFamily
      font.pixelSize: 10
      wrapMode: Text.WrapAtWordBoundaryOrAnywhere
      horizontalAlignment: Text.AlignHCenter
    }
  }

  Timer {
    id: showTimer
    interval: root.delay
    onTriggered: root.ready = true
  }

  onRequestedChanged: {
    if (!requested) {
      showTimer.stop();
      ready = false;
    } else if (delay <= 0) {
      ready = true;
    } else {
      showTimer.restart();
    }
  }
}
