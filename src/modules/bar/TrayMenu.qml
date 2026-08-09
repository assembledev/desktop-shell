pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Wayland
import Quickshell.Widgets
import "../common"

Scope {
  id: root

  required property var shellScreen
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

    closeTimer.stop();
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
      inputLayer.forceActiveFocus(Qt.PopupFocusReason);
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
    closeTimer.restart();
  }

  function closeImmediately() {
    if (!rendered)
      return;
    const fromShelf = sourceFromShelf;
    closeTimer.stop();
    pageTransition.stop();
    expanded = false;
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

  Timer {
    id: closeTimer
    interval: 130
    repeat: false
    onTriggered: {
      if (root.expanded)
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

  SequentialAnimation {
    id: pageTransition

    ParallelAnimation {
      NumberAnimation {
        target: menuPage
        property: "opacity"
        to: 0
        duration: 65
        easing.type: Easing.InCubic
      }
      NumberAnimation {
        target: menuPage
        property: "x"
        to: -root.navigationDirection * 10
        duration: 80
        easing.type: Easing.InCubic
      }
    }

    ScriptAction {
      script: {
        root.menuStack = root.pendingMenuStack;
        menuPage.x = root.navigationDirection * 12;
      }
    }

    ParallelAnimation {
      NumberAnimation {
        target: menuPage
        property: "opacity"
        to: 1
        duration: 105
        easing.type: Easing.OutCubic
      }
      NumberAnimation {
        target: menuPage
        property: "x"
        to: 0
        duration: 135
        easing.type: Easing.OutCubic
      }
    }

    onStopped: {
      menuPage.opacity = 1;
      menuPage.x = 0;
      root.navigating = false;
    }
  }

  PanelWindow {
    id: menuWindow

    screen: root.shellScreen
    visible: root.rendered
    color: "transparent"
    exclusiveZone: 0
    WlrLayershell.namespace: "quickshell:trayMenu"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    FocusScope {
      id: inputLayer
      anchors.fill: parent
      focus: root.rendered

      MouseArea {
        anchors.fill: parent
        onClicked: root.closeMenu()
      }

      Rectangle {
        id: menuCard

        x: root.menuX
        y: root.menuTop + (root.expanded ? 0 : -5)
        width: root.menuWidth
        height: root.menuHeight
        radius: 14
        color: theme.surfaceGlassStrong
        border.color: Qt.alpha(theme.borderSubtle, 0.78)
        border.width: 1
        clip: true
        opacity: root.expanded ? 1 : 0
        scale: root.expanded ? 1 : 0.965
        transformOrigin: Item.TopRight

        Behavior on y {
          NumberAnimation { duration: 145; easing.type: Easing.OutCubic }
        }
        Behavior on height {
          NumberAnimation { duration: 155; easing.type: Easing.OutCubic }
        }
        Behavior on opacity {
          NumberAnimation { duration: 105; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
          NumberAnimation { duration: 145; easing.type: Easing.OutBack }
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
          border.color: Qt.alpha(theme.foreground, 0.045)
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
            color: theme.text
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
            color: root.depth > 1 ? theme.blue : theme.mutedAlt
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
              ? Qt.alpha(theme.blue, 0.6)
              : Qt.alpha(theme.borderSubtle, 0.55)
            border.width: 1

            Behavior on color {
              ColorAnimation { duration: 90 }
            }

            Text {
              anchors.centerIn: parent
              anchors.verticalCenterOffset: -1
              text: "‹"
              color: theme.text
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
                  color: theme.mutedAlt
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
                      ColorAnimation { duration: 85 }
                    }
                  }

                  Rectangle {
                    visible: !entryRow.modelData.isSeparator && entryMouse.containsMouse
                    x: 4
                    width: 2
                    height: 16
                    radius: 1
                    anchors.verticalCenter: parent.verticalCenter
                    color: theme.blue
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
                        ? theme.blue
                        : "transparent"
                      border.color: entryRow.checked || entryRow.partiallyChecked
                        ? Qt.alpha(theme.blue, 0.95)
                        : theme.mutedAlt
                      border.width: 1

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
                      ? Qt.alpha(theme.yellow, 0.9)
                      : entryRow.modelData.enabled ? theme.text : theme.mutedAlt
                    font.family: theme.fontFamily
                    font.pixelSize: entryRow.sectionLabel ? 11 : 12
                    font.bold: entryRow.sectionLabel || entryRow.modelData.hasChildren
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight

                    Behavior on x {
                      NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
                    }
                  }

                  Text {
                    visible: !entryRow.modelData.isSeparator && entryRow.modelData.hasChildren
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: -1
                    text: "›"
                    color: entryMouse.containsMouse ? theme.blue : theme.mutedAlt
                    font.family: theme.fontFamily
                    font.pixelSize: 20
                    font.bold: true
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
        enabled: root.rendered
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
