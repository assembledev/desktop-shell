pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "../common"

Scope {
  id: root
  property var taskHost: null
  function cancelTask() { closeDetails(); }
  onOpenChanged: { if (!open && taskHost) taskHost.releaseTask(root); }

  required property var controller
  required property var barSurface
  property string controlId: ""
  property bool open: false
  property real anchorCenterX: 0
  readonly property var control: controller.controls.find(item => item.id === controlId) || null
  readonly property var current: controller.status(control)
  readonly property var profiles: controller.profiles(control)
  readonly property var screen: placement.screen
  readonly property alias surface: window

  Theme { id: theme }
  ShellConfig { id: configuration }
  ScreenPlacement { id: placement; configuration: configuration; onRemoved: root.closeDetails() }
  MotionTransition { id: transition; requested: root.open }

  function openDetails(controlId, screen, trigger) {
    if (!controller.controls.some(item => item.id === controlId) || !placement.capture(screen)) return;
    if (taskHost) taskHost.requestTask(root, placement.screen);
    root.controlId = controlId;
    anchorCenterX = trigger ? trigger.mapToItem(null, trigger.width / 2, trigger.height).x : root.screen.width / 2;
    window.keyboardRequested = screen === undefined;
    open = true;
    controller.statusRequested(controlId);
    if (window.keyboardRequested)
      Qt.callLater(() => choices.itemAt(0)?.forceActiveFocus());
  }
  function closeDetails() { open = false; }
  function toggleDetails(controlId, screen, trigger) {
    if (open && root.controlId === controlId && placement.matches(screen)) closeDetails();
    else openDetails(controlId, screen, trigger);
  }
  onControlChanged: { if (open && !control) closeDetails(); }

  BarOverlayWindow {
    id: window
    barSurface: root.barSurface
    targetScreen: root.screen
    requested: root.open
    presented: transition.presented
    surfaceNamespace: "quickshell:network-profiles"

    MouseArea { anchors.fill: parent; enabled: root.open; onClicked: root.closeDetails() }
    FocusScope {
      anchors.fill: parent
      focus: root.open
      Shortcut { sequence: "Esc"; enabled: root.open; onActivated: root.closeDetails() }
      Rectangle {
        anchors.top: parent.top
        anchors.topMargin: theme.barPopoverGap
        x: Math.max(12, Math.min(root.anchorCenterX - width / 2, window.width - width - 12))
        width: Math.min(320, Math.max(1, window.width - 24))
        height: Math.min(content.implicitHeight + 32, Math.max(1, window.height - 16))
        radius: theme.groupRadius
        color: theme.surface
        border.color: theme.borderMuted
        border.width: 1
        clip: true
        opacity: transition.progress
        scale: 0.94 + transition.progress * 0.06
        transformOrigin: Item.Top
        transform: Translate { y: (1 - transition.progress) * -10 }
        MouseArea { anchors.fill: parent; onClicked: mouse => mouse.accepted = true }
        Flickable {
          anchors.fill: parent
          contentWidth: width
          contentHeight: content.implicitHeight + 32
          boundsBehavior: Flickable.StopAtBounds
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
          ColumnLayout {
            id: content
            x: 16
            y: 16
            width: parent.width - 32
            spacing: 6
            RowLayout {
              Layout.fillWidth: true
              Text {
                Layout.fillWidth: true
                text: (root.control?.label || root.controlId) + " profiles"
                color: theme.textPrimary
                font.family: theme.uiFontFamily
                font.pixelSize: 16
                font.bold: true
                elide: Text.ElideRight
              }
              ShellButton { colors: theme; glyph: "close"; tooltip: "Close profiles"; onClicked: root.closeDetails() }
            }
            Repeater {
              id: choices
              model: root.profiles
              delegate: Button {
                id: choice
                required property var modelData
                readonly property bool selected: root.current.selectedProfile === modelData.id
                Layout.fillWidth: true
                implicitHeight: 40
                padding: 8
                hoverEnabled: true
                enabled: !root.current.busy
                Accessible.name: modelData.label
                Accessible.role: Accessible.RadioButton
                Accessible.checked: selected
                onClicked: root.controller.selectProfile(root.control, modelData.id)
                contentItem: RowLayout {
                  spacing: 10
                  Text {
                    Layout.fillWidth: true
                    text: choice.modelData.label
                    color: theme.textPrimary
                    font.family: theme.uiFontFamily
                    font.pixelSize: 14
                    elide: Text.ElideRight
                  }
                  ShellSymbol { symbol: "check"; size: 18; tint: theme.accent; visible: choice.selected }
                }
                background: Rectangle {
                  radius: theme.controlRadius
                  color: choice.hovered || choice.visualFocus ? theme.surfaceHover : "transparent"
                }
                HoverHandler { cursorShape: choice.enabled ? Qt.PointingHandCursor : Qt.BusyCursor }
              }
            }
            Text {
              Layout.fillWidth: true
              visible: Boolean(root.current.error)
              text: String(root.current.error || "")
              color: theme.danger
              font.family: theme.uiFontFamily
              font.pixelSize: 13
              wrapMode: Text.Wrap
            }
          }
        }
      }
    }
  }
}
