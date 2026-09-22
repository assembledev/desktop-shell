pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../common"
import "DisplayGeometry.js" as Geometry

Rectangle {
  id: arrangement
  Theme { id: theme }
  required property var draft
  required property var outputs
  property string selectedName: ""
  signal selected(string name)
  signal moved(string name, real x, real y)

  readonly property var activeOutputs: outputs.filter(function(output) { return Boolean(output.enabled); })
  readonly property var viewport: Geometry.viewport(activeOutputs, draft, width, height, 18)
  readonly property bool mirrored: activeOutputs.some(output => String(output.mirror || "").length > 0)

  implicitHeight: activeOutputs.length > 1 ? 188 : 132
  radius: 8
  clip: true
  color: Qt.alpha(theme.surfaceGlass, 0.52)
  border.color: Qt.alpha(theme.borderSubtle, 0.66)
  border.width: 1

  Repeater {
    model: arrangement.activeOutputs

    delegate: Rectangle {
      id: displayTile
      required property var modelData
      required property int index
      readonly property var output: modelData
      readonly property var box: Geometry.rect(output, arrangement.draft)
      readonly property real overlapOffset: arrangement.mirrored ? index * 6 : 0
      readonly property real baseX: arrangement.viewport.x
        + (box.x - arrangement.viewport.minX) * arrangement.viewport.scale + overlapOffset
      readonly property real baseY: arrangement.viewport.y
        + (box.y - arrangement.viewport.minY) * arrangement.viewport.scale + overlapOffset
      property bool dragging: false
      property real dragX: baseX
      property real dragY: baseY
      property var dragPosition: ({ x: box.x, y: box.y })

      x: dragging ? dragX : baseX
      y: dragging ? dragY : baseY
      width: Math.max(1, box.width * arrangement.viewport.scale)
      height: Math.max(1, box.height * arrangement.viewport.scale)
      radius: 6
      color: arrangement.selectedName === String(output.name)
        ? Qt.alpha(theme.info, 0.22)
        : Qt.alpha(theme.surfaceRaised, 0.92)
      border.color: arrangement.selectedName === String(output.name)
        ? theme.info
        : Qt.alpha(theme.borderSubtle, 0.88)
      border.width: arrangement.selectedName === String(output.name) ? 2 : 1
      z: dragging ? 4 : (arrangement.selectedName === String(output.name) ? 2 : 1)

      Behavior on x {
        enabled: !displayTile.dragging
        MotionNumberAnimation { role: MotionNumberAnimation.FocusTravel }
      }
      Behavior on y {
        enabled: !displayTile.dragging
        MotionNumberAnimation { role: MotionNumberAnimation.FocusTravel }
      }

      ColumnLayout {
        anchors.centerIn: parent
        width: Math.max(1, parent.width - 16)
        spacing: 2

        Text {
          Layout.fillWidth: true
          text: String(displayTile.index + 1)
          color: theme.textPrimary
          font.family: theme.fontFamily
          font.pixelSize: 18
          font.bold: true
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          text: String(displayTile.output.name)
          color: arrangement.selectedName === String(displayTile.output.name) ? theme.info : theme.textMuted
          font.family: theme.fontFamily
          font.pixelSize: 8
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
        }
      }

      MouseArea {
        id: displayTileMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: arrangement.activeOutputs.length < 2 || arrangement.mirrored
          ? Qt.PointingHandCursor : pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        property real pointerStartX: 0
        property real pointerStartY: 0
        property real tileStartX: 0
        property real tileStartY: 0

        onPressed: function(mouse) {
          arrangement.selected(String(displayTile.output.name));
          const pointer = mapToItem(arrangement, mouse.x, mouse.y);
          pointerStartX = pointer.x;
          pointerStartY = pointer.y;
          tileStartX = displayTile.x;
          tileStartY = displayTile.y;
          displayTile.dragX = displayTile.x;
          displayTile.dragY = displayTile.y;
          displayTile.dragging = false;
        }

        onPositionChanged: function(mouse) {
          if (!pressed || arrangement.activeOutputs.length < 2 || arrangement.mirrored)
            return;
          const pointer = mapToItem(arrangement, mouse.x, mouse.y);
          if (!displayTile.dragging && Math.abs(pointer.x - pointerStartX) + Math.abs(pointer.y - pointerStartY) < 4)
            return;
          displayTile.dragging = true;
          const rawX = Math.max(-displayTile.width / 2, Math.min(
            arrangement.width - displayTile.width / 2,
            tileStartX + pointer.x - pointerStartX
          ));
          const rawY = Math.max(-displayTile.height / 2, Math.min(
            arrangement.height - displayTile.height / 2,
            tileStartY + pointer.y - pointerStartY
          ));
          const x = arrangement.viewport.minX + (rawX - arrangement.viewport.x) / arrangement.viewport.scale;
          const y = arrangement.viewport.minY + (rawY - arrangement.viewport.y) / arrangement.viewport.scale;
          const snapped = Geometry.snap(arrangement.activeOutputs, arrangement.draft,
            String(displayTile.output.name), x, y);
          displayTile.dragPosition = snapped;
          displayTile.dragX = arrangement.viewport.x + (snapped.x - arrangement.viewport.minX) * arrangement.viewport.scale;
          displayTile.dragY = arrangement.viewport.y + (snapped.y - arrangement.viewport.minY) * arrangement.viewport.scale;
        }

        onReleased: {
          if (!displayTile.dragging)
            return;
          arrangement.moved(String(displayTile.output.name), displayTile.dragPosition.x, displayTile.dragPosition.y);
          displayTile.dragging = false;
        }

        onCanceled: {
          displayTile.dragging = false;
        }
      }
    }
  }
}
