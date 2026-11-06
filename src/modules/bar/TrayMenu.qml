pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import "../common"

Scope {
  id: root
  property var taskHost: null
  Component.onDestruction: { if (taskHost) taskHost.releaseTask(root); }
  function cancelTask() { closeMenu(); }

  required property var shellScreen
  required property var barSurface
  readonly property alias surface: menuWindow
  property bool barVisible: true

  property SystemTrayItem trayItem: null
  property int openRequest: 0
  property bool rendered: false
  property bool expanded: false
  property bool sourceFromShelf: false
  property Item popupAnchor: null
  property Item sourceShelf: null
  property var menuStack: []
  property int navigationDirection: 1
  readonly property real menuWidth: popupPlacement.width
  readonly property real menuTop: popupPlacement.y
  readonly property real maximumListHeight: Math.max(0, popupPlacement.maximumHeight - 70)
  readonly property int listHeight: Math.min(menuColumn.implicitHeight, maximumListHeight)
  readonly property int menuHeight: 70 + listHeight
  readonly property real menuX: popupPlacement.x
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
      root.menuStack = [];
      root.rendered = false;
      root.trayItem = null;
      root.sourceFromShelf = false;
      root.closed(fromShelf);
    }
  }

  BarPopupPlacement {
    id: popupPlacement
    trigger: root.popupAnchor
    belowItem: root.sourceShelf
    sourceTop: root.barSurface?.height || 0
    surfaceTop: 0
    screenWidth: root.shellScreen?.width || 0
    screenHeight: root.shellScreen?.height || 0
    barHeight: root.barSurface?.height || 0
    preferredWidth: 332
    gap: theme.barPopoverGap
    active: root.expanded
    onAnchorLost: root.closeMenu()
  }

  function openFor(item, trigger, shelf) {
    if (!item || !item.hasMenu)
      return;

    if (rendered && expanded && trayItem === item) {
      closeMenu();
      return;
    }

    if (taskHost)
      taskHost.requestTask(root, shellScreen);
    pageTransition.stop();
    menuStack = [];
    trayItem = item;
    sourceFromShelf = shelf !== null;
    popupAnchor = trigger;
    sourceShelf = shelf;
    menuStack = [{ handle: item.menu, title: "", focusIndex: 0 }];
    menuPage.opacity = 1;
    menuPage.x = 0;

    const request = ++openRequest;
    const wasRendered = rendered;
    rendered = true;
    expanded = false;
    Qt.callLater(function() {
      if (request !== root.openRequest || !root.rendered || root.trayItem !== item)
        return;
      root.expanded = true;
      menuWindow.keyboardRequested = true;
      Qt.callLater(root.focusCurrentMenu);
      if (!wasRendered)
        root.opened(root.sourceFromShelf);
    });
  }

  function closeMenu() {
    if (!expanded) {
      closeImmediately();
      return;
    }
    if (taskHost)
      taskHost.releaseTask(root);
    openRequest++;
    pageTransition.stop();
    expanded = false;
  }

  function closeImmediately() {
    if (taskHost)
      taskHost.releaseTask(root);
    openRequest++;
    if (!rendered)
      return;
    const fromShelf = sourceFromShelf;
    pageTransition.stop();
    expanded = false;
    surfaceTransition.snapDismissed();
    menuStack = [];
    rendered = false;
    trayItem = null;
    sourceFromShelf = false;
    closed(fromShelf);
  }

  function navigate(nextStack, direction) {
    if (!nextStack || nextStack.length === 0)
      return;
    pageTransition.stop();
    navigationDirection = direction;
    // Update before animating so repeated input uses the current submenu.
    menuStack = nextStack;
    menuFlickable.contentY = 0;
    pageTransition.restart();
    Qt.callLater(root.focusCurrentMenu);
  }

  function enterSubmenu(entry) {
    if (!entry || !entry.enabled || !entry.hasChildren)
      return;
    navigate(menuStack.concat([{ handle: entry, title: entry.text, focusIndex: 0 }]), 1);
  }

  function leaveSubmenu() {
    if (depth <= 1)
      return;
    navigate(menuStack.slice(0, depth - 1), -1);
  }

  function focusHoveredAction() {
    if (!expanded || !menuInputIntent.pointerActive) return;
    for (let i = 0; i < entryRepeater.count; i++) {
      const row = entryRepeater.itemAt(i);
      if (row?.enabled && row.visible && row.hovered) {
        row.forceActiveFocus(Qt.MouseFocusReason);
        return;
      }
    }
  }

  function focusAction(index, direction) {
    menuInputIntent.claimKeyboard();
    menuColumn.forceLayout();
    const count = entryRepeater.count;
    for (let offset = 0; offset < count; offset++) {
      const row = entryRepeater.itemAt(((index + offset * direction) % count + count) % count);
      if (row && row.enabled && row.visible) {
        row.forceActiveFocus(Qt.TabFocusReason);
        return;
      }
    }
    if (backButton.visible)
      backButton.forceActiveFocus(Qt.TabFocusReason);
    else
      inputLayer.forceActiveFocus();
  }

  function focusCurrentMenu() {
    if (expanded)
      focusAction(menuStack[depth - 1]?.focusIndex || 0, 1);
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
        root.menuStack = [{ handle: root.trayItem.menu, title: "", focusIndex: 0 }];
    }
  }

  ParallelAnimation {
    id: pageTransition

    MotionNumberAnimation {
      target: menuPage
      property: "opacity"
      from: 0.55
      to: 1
      role: MotionNumberAnimation.Content
    }
    MotionNumberAnimation {
      target: menuPage
      property: "x"
      from: root.navigationDirection * 12
      to: 0
      role: MotionNumberAnimation.Content
    }

    onStopped: {
      menuPage.opacity = 1;
      menuPage.x = 0;
    }
  }

  BarOverlayWindow {
    id: menuWindow

    barSurface: root.barSurface
    requested: root.expanded
    presented: surfaceTransition.presented
    surfaceNamespace: "quickshell:trayMenu"
    popupContent: menuCard
    onDismissRequested: root.closeMenu()
    margins.top: 0

    FocusScope {
      id: inputLayer
      anchors.fill: parent
      focus: root.expanded

      InputIntent {
        id: menuInputIntent
        surface: inputLayer
        onPointerActivity: Qt.callLater(root.focusHoveredAction)
      }

      Keys.onDownPressed: root.focusAction(0, 1)
      Keys.onUpPressed: root.focusAction(entryRepeater.count - 1, -1)
      Keys.onPressed: function(event) {
        menuInputIntent.claimKeyboard();
        if (event.key === Qt.Key_Home || event.key === Qt.Key_End) {
          root.focusAction(event.key === Qt.Key_Home ? 0 : entryRepeater.count - 1, event.key === Qt.Key_Home ? 1 : -1);
          event.accepted = true;
        } else if ((event.key === Qt.Key_Left || event.key === Qt.Key_Backspace) && root.depth > 1) {
          root.leaveSubmenu();
          event.accepted = true;
        }
      }

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
        color: theme.surface
        border.color: theme.borderSubtle
        border.width: 1
        clip: true
        opacity: surfaceTransition.progress
        scale: 0.9 + surfaceTransition.progress * 0.1
        transformOrigin: Item.Top

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
            font.family: theme.uiFontFamily
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
            font.family: theme.uiFontFamily
            font.pixelSize: 10
            font.bold: root.depth > 1
            elide: Text.ElideRight
          }

          Button {
            id: backButton
            visible: root.depth > 1
            enabled: root.expanded
            width: 30
            height: 30
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            padding: 0
            focusPolicy: Qt.StrongFocus
            hoverEnabled: true
            Accessible.name: "Back to previous menu"
            scale: down ? 0.88 : (hovered ? 1.04 : 1)
            Keys.onReturnPressed: click()
            Keys.onEnterPressed: click()
            onClicked: root.leaveSubmenu()

            Behavior on scale {
              MotionNumberAnimation { role: MotionNumberAnimation.Feedback }
            }

            contentItem: ShellSymbol {
              symbol: "back"
              size: 16
              tint: theme.textSecondary
            }

            background: Rectangle {
              radius: 9
              color: backButton.hovered || backButton.visualFocus ? theme.surfaceHover : theme.surfaceAccent
              border.color: backButton.hovered || backButton.visualFocus
                ? Qt.alpha(theme.accent, 0.6)
                : theme.borderSubtle
              border.width: 1

              Behavior on color {
                MotionColorAnimation { role: MotionNumberAnimation.Feedback }
              }
              Behavior on border.color {
                MotionColorAnimation { role: MotionNumberAnimation.Feedback }
              }
            }

            HoverHandler {
              enabled: backButton.enabled
              cursorShape: Qt.PointingHandCursor
            }
          }
        }

        Rectangle {
          x: 12
          y: 55
          width: parent.width - 24
          height: 1
          color: theme.borderSubtle
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
                  font.family: theme.uiFontFamily
                  font.pixelSize: 11
                }
              }

              Repeater {
                id: entryRepeater
                model: menuOpener.children
                onItemAdded: Qt.callLater(root.focusCurrentMenu)

                delegate: MenuItem {
                  id: entryRow

                  required property int index
                  required property QsMenuEntry modelData
                  readonly property bool toggleEntry: (modelData?.buttonType ?? QsMenuButtonType.None) !== QsMenuButtonType.None
                  readonly property bool radioEntry: modelData?.buttonType === QsMenuButtonType.RadioButton
                  readonly property bool entryChecked: modelData?.checkState === Qt.Checked
                  readonly property bool partiallyChecked: modelData?.checkState === Qt.PartiallyChecked

                  visible: modelData !== null
                  width: menuColumn.width
                  height: modelData?.isSeparator ? 11 : 38
                  enabled: root.expanded && Boolean(modelData?.enabled) && !modelData?.isSeparator
                  opacity: modelData?.enabled || modelData?.isSeparator ? 1 : 0.48
                  text: modelData?.text || ""
                  focusPolicy: Qt.StrongFocus
                  hoverEnabled: true
                  highlighted: (menuInputIntent.pointerActive && hovered) || activeFocus
                  padding: 0
                  indicator: null
                  arrow: null
                  background: null
                  Accessible.ignored: modelData?.isSeparator ?? true
                  Accessible.checkable: toggleEntry
                  Accessible.checked: entryChecked

                  Keys.onUpPressed: root.focusAction(index - 1, -1)
                  Keys.onDownPressed: root.focusAction(index + 1, 1)
                  Keys.onRightPressed: function(event) {
                    menuInputIntent.claimKeyboard();
                    if (entryRow.modelData?.hasChildren)
                      root.enterSubmenu(entryRow.modelData);
                    else
                      event.accepted = false;
                  }

                  onHoveredChanged: {
                    if (hovered) root.focusHoveredAction();
                  }
                  onActiveFocusChanged: {
                    if (!activeFocus || root.depth === 0)
                      return;
                    root.menuStack[root.depth - 1].focusIndex = index;
                    if (y < menuFlickable.contentY)
                      menuFlickable.contentY = y;
                    else if (y + height > menuFlickable.contentY + menuFlickable.height)
                      menuFlickable.contentY = y + height - menuFlickable.height;
                  }
                  onTriggered: {
                    if (!modelData)
                      return;
                    if (modelData.hasChildren) {
                      root.enterSubmenu(modelData);
                    } else {
                      modelData.triggered();
                      root.closeMenu();
                    }
                  }

                  HoverHandler {
                    enabled: entryRow.enabled
                    cursorShape: Qt.PointingHandCursor
                  }

                  contentItem: Item {
                    Rectangle {
                      visible: Boolean(entryRow.modelData?.isSeparator)
                      x: 8
                      width: parent.width - 16
                      height: 1
                      anchors.verticalCenter: parent.verticalCenter
                      color: theme.borderSubtle
                    }

                    Rectangle {
                      visible: !entryRow.modelData?.isSeparator
                      anchors.fill: parent
                      anchors.leftMargin: 1
                      anchors.rightMargin: 1
                      anchors.topMargin: 1
                      anchors.bottomMargin: 1
                      radius: 9
                      color: entryRow.highlighted ? theme.surfaceHover : "transparent"
                      border.color: entryRow.highlighted
                        ? theme.borderSubtle
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
                      visible: !entryRow.modelData?.isSeparator && entryRow.highlighted
                      x: 4
                      width: 2
                      height: 16
                      radius: 1
                      anchors.verticalCenter: parent.verticalCenter
                      color: theme.accent
                    }

                    Item {
                      visible: !entryRow.modelData?.isSeparator
                      x: 12
                      width: 20
                      height: parent.height

                      IconImage {
                        visible: !entryRow.toggleEntry && entryRow.modelData?.icon.length > 0
                        width: 18
                        height: 18
                        anchors.centerIn: parent
                        source: entryRow.modelData?.icon || ""
                      }

                      Rectangle {
                        id: toggleFrame
                        visible: entryRow.toggleEntry
                        width: 16
                        height: 16
                        radius: entryRow.radioEntry ? 8 : 4
                        anchors.centerIn: parent
                        color: entryRow.entryChecked || entryRow.partiallyChecked
                          ? theme.accent
                          : "transparent"
                        border.color: entryRow.entryChecked || entryRow.partiallyChecked
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
                          visible: entryRow.radioEntry && entryRow.entryChecked
                          width: 6
                          height: 6
                          radius: 3
                          anchors.centerIn: parent
                          color: theme.bgSolid
                        }

                        Text {
                          visible: !entryRow.radioEntry && (entryRow.entryChecked || entryRow.partiallyChecked)
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
                      visible: !entryRow.modelData?.isSeparator
                      x: 42 + (entryRow.highlighted ? 2 : 0)
                      width: parent.width - x - (entryRow.modelData?.hasChildren ? 30 : 12)
                      height: parent.height
                      text: entryRow.text
                      color: entryRow.modelData?.enabled ? theme.textSecondary : theme.textMuted
                      font.family: theme.uiFontFamily
                      font.pixelSize: 12
                      font.bold: Boolean(entryRow.modelData?.hasChildren)
                      verticalAlignment: Text.AlignVCenter
                      elide: Text.ElideRight

                      Behavior on x {
                        MotionNumberAnimation { role: MotionNumberAnimation.Feedback }
                      }
                    }

                    ShellSymbol {
                      visible: !entryRow.modelData?.isSeparator && Boolean(entryRow.modelData?.hasChildren)
                      anchors.right: parent.right
                      anchors.rightMargin: 12
                      anchors.verticalCenter: parent.verticalCenter
                      symbol: "right"
                      size: 16
                      tint: entryRow.highlighted ? theme.accent : theme.textMuted
                      scale: entryRow.highlighted ? 1.14 : 1

                      Behavior on scale {
                        MotionNumberAnimation { role: MotionNumberAnimation.Feedback }
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
        onActivated: root.depth > 1 ? root.leaveSubmenu() : root.closeMenu()
      }
    }
  }

  // Child handles belong to the root DBus menu tree; retain it while browsing.
  QsMenuOpener {
    menu: root.rendered ? root.trayItem?.menu : null
  }

  QsMenuOpener {
    id: menuOpener
    menu: root.activeMenu
  }
}
