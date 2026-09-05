pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import "../common"

Scope {
  id: root

  required property var shellScreen
  required property var barSurface
  property bool barVisible: true

  property SystemTrayItem trayItem: null
  property bool rendered: false
  property bool expanded: false
  property bool sourceFromShelf: false
  property real anchorCenterX: 0
  property real anchorBottomY: 0
  property var menuStack: []
  property var pendingMenuStack: []
  property int navigationDirection: 1
  property bool navigating: false
  readonly property int edgeMargin: 12
  readonly property real availableWidth: Number(menuWindow.width || shellScreen?.width || 0)
  readonly property real availableHeight: Number(menuWindow.height || shellScreen?.height || 0)
  readonly property int menuWidth: Math.max(180, Math.min(332, availableWidth - edgeMargin * 2))
  readonly property real menuTop: Math.max(6, anchorBottomY + 7)
  readonly property int maximumListHeight: Math.max(38, availableHeight - menuTop - 82)
  readonly property int listHeight: Math.min(menuColumn.implicitHeight, maximumListHeight)
  readonly property int menuHeight: 70 + listHeight
  readonly property real menuX: clamp(anchorCenterX - menuWidth + 24,
    edgeMargin, availableWidth - menuWidth - edgeMargin)
  readonly property int depth: menuStack.length
  readonly property var activeMenu: depth > 0 ? menuStack[depth - 1].handle : null
  readonly property string applicationTitle: {
    const title = String(trayItem?.title || trayItem?.tooltipTitle || trayItem?.id || "").trim();
    return title.length > 0 ? title : "Tray application";
  }
  readonly property string contextTitle: {
    if (depth > 1)
      return String(menuStack[depth - 1].title || "Submenu");
    return String(trayItem?.tooltipDescription || "").trim();
  }

  signal opened(bool fromShelf)
  signal closed(bool fromShelf)

  Theme {
    id: theme
  }

  MotionTransition {
    id: surfaceTransition
    requested: root.expanded
    onDismissed: {
      if (root.expanded || !root.rendered)
        return;
      const fromShelf = root.sourceFromShelf;
      root.rendered = false;
      root.trayItem = null;
      root.sourceFromShelf = false;
      root.menuStack = [];
      root.pendingMenuStack = [];
      root.closed(fromShelf);
    }
  }

  function clamp(value, minimum, maximum) {
    return Math.max(minimum, Math.min(value, Math.max(minimum, maximum)));
  }

  function openFor(item, centerX, bottomY, fromShelf) {
    if (!item || !item.hasMenu)
      return;

    if (rendered && expanded && trayItem === item) {
      closeMenu();
      return;
    }

    pageTransition.stop();
    navigating = false;
    trayItem = item;
    sourceFromShelf = Boolean(fromShelf);
    anchorCenterX = Number(centerX || 0);
    anchorBottomY = Number.isFinite(Number(bottomY)) ? Number(bottomY) : 0;
    menuStack = [{ handle: item.menu, title: "" }];
    pendingMenuStack = [];
    menuPage.opacity = 1;
    menuPage.x = 0;

    const wasRendered = rendered;
    rendered = true;
    expanded = false;
    Qt.callLater(function() {
      if (!root.rendered || root.trayItem !== item)
        return;
      root.expanded = true;
      if (!wasRendered)
        root.opened(root.sourceFromShelf);
    });
  }

  function closeMenu() {
    if (!rendered)
      return;
    pageTransition.stop();
    navigating = false;
    expanded = false;
  }

  function closeImmediately() {
    if (!rendered)
      return;
    const fromShelf = sourceFromShelf;
    pageTransition.stop();
    expanded = false;
    surfaceTransition.snapDismissed();
    rendered = false;
    trayItem = null;
    sourceFromShelf = false;
    menuStack = [];
    pendingMenuStack = [];
    navigating = false;
    closed(fromShelf);
  }

  function navigate(nextStack, direction) {
    if (navigating || !nextStack || nextStack.length === 0)
      return;
    pendingMenuStack = nextStack;
    navigationDirection = direction;
    navigating = true;
    pageTransition.restart();
  }

  function enterSubmenu(entry) {
    if (!entry || !entry.hasChildren)
      return;
    navigate(menuStack.concat([{ handle: entry, title: entry.text }]), 1);
  }

  function leaveSubmenu() {
    if (depth <= 1)
      return;
    navigate(menuStack.slice(0, depth - 1), -1);
  }

  onBarVisibleChanged: {
    if (!barVisible)
      closeImmediately();
  }

  Connections {
    target: root.trayItem
    ignoreUnknownSignals: true

    function onDestroyed() {
      root.closeImmediately();
    }

    function onMenuChanged() {
      if (root.rendered && root.trayItem?.menu)
        root.menuStack = [{ handle: root.trayItem.menu, title: "" }];
    }
  }

  SequentialAnimation {
    id: pageTransition

    ParallelAnimation {
      MotionNumberAnimation {
        target: menuPage
        property: "opacity"
        to: 0
        role: MotionNumberAnimation.SurfaceExit
      }
      MotionNumberAnimation {
        target: menuPage
        property: "x"
        to: -root.navigationDirection * 10
        role: MotionNumberAnimation.SurfaceExit
      }
    }

    ScriptAction {
      script: {
        root.menuStack = root.pendingMenuStack;
        menuPage.x = root.navigationDirection * 12;
      }
    }

    ParallelAnimation {
      MotionNumberAnimation {
        target: menuPage
        property: "opacity"
        to: 1
        role: MotionNumberAnimation.Content
      }
      MotionNumberAnimation {
        target: menuPage
        property: "x"
        to: 0
        role: MotionNumberAnimation.Content
      }
    }

    onStopped: {
      menuPage.opacity = 1;
      menuPage.x = 0;
      root.navigating = false;
    }
  }

  BarOverlayWindow {
    id: menuWindow

    barSurface: root.barSurface
    requested: root.expanded
    presented: surfaceTransition.presented
    surfaceNamespace: "quickshell:trayMenu"

    FocusScope {
      id: inputLayer
      anchors.fill: parent
      focus: root.expanded

      MouseArea {
        anchors.fill: parent
        enabled: root.expanded
        onClicked: root.closeMenu()
      }

      Rectangle {
        id: menuCard

        x: root.menuX
        y: root.menuTop - (1 - surfaceTransition.progress) * 12
        width: root.menuWidth
        height: root.menuHeight
        radius: 14
        color: theme.surfaceGlassStrong
        border.color: Qt.alpha(theme.borderSubtle, 0.78)
        border.width: 1
        clip: true
        opacity: surfaceTransition.progress
        scale: 0.9 + surfaceTransition.progress * 0.1
        transformOrigin: Item.TopRight

        Behavior on height {
          MotionNumberAnimation { role: MotionNumberAnimation.Content }
        }

        MouseArea {
          anchors.fill: parent
          onClicked: function(mouse) { mouse.accepted = true; }
        }

        Rectangle {
          anchors.fill: parent
          anchors.margins: 1
          radius: 13
          color: "transparent"
          border.color: Qt.alpha(theme.textPrimary, 0.045)
          border.width: 1
        }

        Item {
          id: header
          x: 12
          y: 9
          width: parent.width - 24
          height: 40

          Item {
            id: iconWell
            width: 34
            height: 34
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter

            IconImage {
              width: 26
              height: 26
              anchors.centerIn: parent
              source: root.trayItem?.icon || ""
            }
          }

          Text {
            id: titleLabel
            anchors.left: iconWell.right
            anchors.leftMargin: 10
            anchors.right: backButton.visible ? backButton.left : parent.right
            anchors.rightMargin: backButton.visible ? 8 : 0
            y: contextLabel.visible ? 2 : Math.round((parent.height - implicitHeight) / 2)
            text: root.applicationTitle
            color: theme.textSecondary
            font.family: theme.fontFamily
            font.pixelSize: 13
            font.bold: true
            elide: Text.ElideRight
          }

          Text {
            id: contextLabel
            anchors.left: titleLabel.left
            anchors.right: titleLabel.right
            anchors.top: titleLabel.bottom
            anchors.topMargin: 1
            visible: text.length > 0
            text: root.contextTitle
            color: root.depth > 1 ? theme.accent : theme.textMuted
            font.family: theme.fontFamily
            font.pixelSize: 10
            font.bold: root.depth > 1
            elide: Text.ElideRight
          }

          Rectangle {
            id: backButton
            visible: root.depth > 1
            width: 30
            height: 30
            radius: 9
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            color: backMouse.containsMouse ? theme.surfaceHover : theme.surfaceAccent
            border.color: backMouse.containsMouse
              ? Qt.alpha(theme.accent, 0.6)
              : Qt.alpha(theme.borderSubtle, 0.55)
            border.width: 1
            scale: backMouse.pressed ? 0.88 : (backMouse.containsMouse ? 1.04 : 1)

            Behavior on color {
              MotionColorAnimation { role: MotionNumberAnimation.Feedback }
            }
            Behavior on border.color {
              MotionColorAnimation { role: MotionNumberAnimation.Feedback }
            }
            Behavior on scale {
              MotionNumberAnimation { role: MotionNumberAnimation.Feedback }
            }

            Text {
              anchors.centerIn: parent
              anchors.verticalCenterOffset: -1
              text: "‹"
              color: theme.textSecondary
              font.family: theme.fontFamily
              font.pixelSize: 23
              font.bold: true
            }

            MouseArea {
              id: backMouse
              anchors.fill: parent
              enabled: !root.navigating
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.leaveSubmenu()
            }
          }
        }

        Rectangle {
          x: 12
          y: 55
          width: parent.width - 24
          height: 1
          color: Qt.alpha(theme.borderSubtle, 0.68)
        }

        Item {
          id: menuPage
          x: 0
          y: 62
          width: parent.width
          height: root.listHeight

          Flickable {
            id: menuFlickable
            x: 7
            width: parent.width - 14
            height: parent.height
            contentWidth: width
            contentHeight: menuColumn.implicitHeight
            clip: true
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds

            Column {
              id: menuColumn
              width: menuFlickable.width

              Item {
                width: parent.width
                height: visible ? 38 : 0
                visible: menuOpener.children.values.length === 0

                Text {
                  anchors.centerIn: parent
                  text: "No actions available"
                  color: theme.textMuted
                  font.family: theme.fontFamily
                  font.pixelSize: 11
                }
              }

              Repeater {
                model: menuOpener.children

                delegate: Item {
                  id: entryRow

                  required property QsMenuEntry modelData
                  readonly property bool toggleEntry: modelData.buttonType !== QsMenuButtonType.None
                  readonly property bool radioEntry: modelData.buttonType === QsMenuButtonType.RadioButton
                  readonly property bool checked: modelData.checkState === Qt.Checked
                  readonly property bool partiallyChecked: modelData.checkState === Qt.PartiallyChecked
                  readonly property bool sectionLabel: !modelData.isSeparator
                    && !modelData.enabled
                    && !toggleEntry
                    && !modelData.hasChildren
                    && modelData.icon.length === 0

                  width: menuColumn.width
                  height: modelData.isSeparator ? 11 : sectionLabel ? 32 : 38
                  opacity: modelData.enabled || modelData.isSeparator || sectionLabel ? 1 : 0.48

                  Rectangle {
                    visible: entryRow.modelData.isSeparator
                    x: 8
                    width: parent.width - 16
                    height: 1
                    anchors.verticalCenter: parent.verticalCenter
                    color: Qt.alpha(theme.borderSubtle, 0.55)
                  }

                  Rectangle {
                    visible: !entryRow.modelData.isSeparator
                    anchors.fill: parent
                    anchors.leftMargin: 1
                    anchors.rightMargin: 1
                    anchors.topMargin: 1
                    anchors.bottomMargin: 1
                    radius: 9
                    color: entryMouse.containsMouse ? theme.surfaceHover : "transparent"
                    border.color: entryMouse.containsMouse
                      ? Qt.alpha(theme.borderSubtle, 0.52)
                      : "transparent"
                    border.width: 1

                    Behavior on color {
                      MotionColorAnimation { role: MotionNumberAnimation.Feedback }
                    }
                    Behavior on border.color {
                      MotionColorAnimation { role: MotionNumberAnimation.Feedback }
                    }
                  }

                  Rectangle {
                    visible: !entryRow.modelData.isSeparator && entryMouse.containsMouse
                    x: 4
                    width: 2
                    height: 16
                    radius: 1
                    anchors.verticalCenter: parent.verticalCenter
                    color: theme.accent
                  }

                  Item {
                    visible: !entryRow.modelData.isSeparator
                    x: 12
                    width: 20
                    height: parent.height

                    IconImage {
                      visible: !entryRow.toggleEntry && entryRow.modelData.icon.length > 0
                      width: 18
                      height: 18
                      anchors.centerIn: parent
                      source: entryRow.modelData.icon
                    }

                    Rectangle {
                      id: toggleFrame
                      visible: entryRow.toggleEntry
                      width: 16
                      height: 16
                      radius: entryRow.radioEntry ? 8 : 4
                      anchors.centerIn: parent
                      color: entryRow.checked || entryRow.partiallyChecked
                        ? theme.accent
                        : "transparent"
                      border.color: entryRow.checked || entryRow.partiallyChecked
                        ? Qt.alpha(theme.accent, 0.95)
                        : theme.textMuted
                      border.width: 1

                      Behavior on color {
                        MotionColorAnimation { role: MotionNumberAnimation.Feedback }
                      }
                      Behavior on border.color {
                        MotionColorAnimation { role: MotionNumberAnimation.Feedback }
                      }

                      Rectangle {
                        visible: entryRow.radioEntry && entryRow.checked
                        width: 6
                        height: 6
                        radius: 3
                        anchors.centerIn: parent
                        color: theme.bgSolid
                      }

                      Text {
                        visible: !entryRow.radioEntry && (entryRow.checked || entryRow.partiallyChecked)
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: -1
                        text: entryRow.partiallyChecked ? "−" : "✓"
                        color: theme.bgSolid
                        font.pixelSize: 11
                        font.bold: true
                      }
                    }
                  }

                  Text {
                    visible: !entryRow.modelData.isSeparator
                    x: 42 + (entryMouse.containsMouse ? 2 : 0)
                    width: parent.width - x - (entryRow.modelData.hasChildren ? 30 : 12)
                    height: parent.height
                    text: entryRow.modelData.text
                    color: entryRow.sectionLabel
                      ? theme.utility
                      : entryRow.modelData.enabled ? theme.textSecondary : theme.textMuted
                    font.family: theme.fontFamily
                    font.pixelSize: entryRow.sectionLabel ? 11 : 12
                    font.bold: entryRow.sectionLabel || entryRow.modelData.hasChildren
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight

                    Behavior on x {
                      MotionNumberAnimation { role: MotionNumberAnimation.Feedback }
                    }
                  }

                  Text {
                    visible: !entryRow.modelData.isSeparator && entryRow.modelData.hasChildren
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: -1
                    text: "›"
                    color: entryMouse.containsMouse ? theme.accent : theme.textMuted
                    font.family: theme.fontFamily
                    font.pixelSize: 20
                    font.bold: true
                    scale: entryMouse.containsMouse ? 1.14 : 1

                    Behavior on scale {
                      MotionNumberAnimation { role: MotionNumberAnimation.Feedback }
                    }
                  }

                  MouseArea {
                    id: entryMouse
                    anchors.fill: parent
                    enabled: !entryRow.modelData.isSeparator
                      && entryRow.modelData.enabled
                      && !root.navigating
                    hoverEnabled: true
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: {
                      if (entryRow.modelData.hasChildren) {
                        root.enterSubmenu(entryRow.modelData);
                      } else {
                        entryRow.modelData.triggered();
                        root.closeMenu();
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }

      Shortcut {
        enabled: root.expanded
        sequence: "Esc"
        onActivated: root.closeMenu()
      }
    }
  }

  QsMenuOpener {
    id: menuOpener
    menu: root.activeMenu
  }
}
