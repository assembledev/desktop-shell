pragma ComponentBehavior: Bound
//@ pragma DefaultEnv QS_NO_RELOAD_POPUP=1

import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../common"

Scope {
  id: shell

  Theme {
    id: theme
  }

  ShellConfig { id: shellConfig }
  MotionTransition {
    id: surfaceTransition
    requested: shell.open
  }

  property string backend: Quickshell.env("WALLPAPER_PICKER_BACKEND")
  property string currentPath: ""
  property var allWallpapers: []
  property bool open: false
  property bool ready: false
  property bool accepted: false
  property bool closing: false
  property bool currentLoaded: false
  property bool listLoaded: false
  property string pendingPreviewPath: ""
  property string previewStartedPath: ""

  function imageUrl(path) {
    if (!path)
      return "";

    var encoded = encodeURI(path).replace(/#/g, "%23").replace(/\?/g, "%3F");
    return encoded[0] === "/" ? "file://" + encoded : encoded;
  }

  function itemAt(index) {
    if (index < 0 || index >= filteredModel.count)
      return null;
    return filteredModel.get(index);
  }

  function currentItem() {
    return itemAt(carousel.currentIndex);
  }

  function applyFilter() {
    var previous = currentItem();
    var previousPath = previous ? previous.path : shell.currentPath;
    var query = search.text.toLowerCase().trim();

    filteredModel.clear();

    for (var i = 0; i < allWallpapers.length; i++) {
      var item = allWallpapers[i];
      if (query.length === 0 || item.relativePath.toLowerCase().indexOf(query) !== -1)
        filteredModel.append(item);
    }

    var nextIndex = 0;
    for (var j = 0; j < filteredModel.count; j++) {
      if (filteredModel.get(j).path === previousPath) {
        nextIndex = j;
        break;
      }
    }

    carousel.currentIndex = filteredModel.count > 0 ? nextIndex : -1;
    previewCurrent();
  }

  function previewCurrent() {
    if (!ready || filteredModel.count === 0)
      return;

    var item = currentItem();
    if (item) {
      pendingPreviewPath = item.path;
      previewDebounce.restart();
    }
  }

  function finishLoading() {
    if (!currentLoaded || !listLoaded)
      return;
    ready = true;
    applyFilter();
    if (open)
      carousel.forceActiveFocus();
  }

  function commitCurrent() {
    if (closing)
      return;

    var item = currentItem();
    if (!item)
      return;

    accepted = true;
    closing = true;
    previewDebounce.stop();
    previewProc.running = false;
    Quickshell.execDetached([backend, "set", item.path]);
    close();
  }

  function cancel() {
    if (closing)
      return;

    closing = true;
    previewDebounce.stop();
    previewProc.running = false;
    if (!accepted && currentPath.length > 0)
      Quickshell.execDetached([backend, "preview", currentPath]);
    close();
  }

  function openPicker() {
    accepted = false;
    closing = false;
    ready = false;
    currentLoaded = false;
    listLoaded = false;
    search.text = "";
    filteredModel.clear();
    open = true;
    currentProc.running = true;
    listProc.running = true;
  }

  function close() {
    open = false;
  }

  IpcHandler {
    target: "wallpaperPicker"
    function pick() { shell.openPicker(); }
    function close() { shell.cancel(); }
  }

  Process {
    id: currentProc
    command: [shell.backend, "current"]
    stdout: StdioCollector {
      onStreamFinished: {
        shell.currentPath = text.trim();
        shell.currentLoaded = true;
        shell.finishLoading();
      }
    }
  }

  Process {
    id: listProc

    command: [shell.backend, "list-json"]

    stdout: StdioCollector {
      onStreamFinished: {
        try {
          shell.allWallpapers = JSON.parse(text);
        } catch (error) {
          shell.allWallpapers = [];
          console.error("wallpaper-picker: failed to parse wallpaper list: " + error);
        }

        shell.listLoaded = true;
        shell.finishLoading();
      }
    }
  }

  Timer {
    id: previewDebounce
    interval: 120
    onTriggered: {
      if (previewProc.running) {
        restart();
        return;
      }
      shell.previewStartedPath = shell.pendingPreviewPath;
      previewProc.exec([shell.backend, "preview", shell.previewStartedPath]);
    }
  }

  Process {
    id: previewProc
    onExited: {
      if (shell.pendingPreviewPath !== shell.previewStartedPath)
        previewDebounce.restart();
    }
  }

  ListModel {
    id: filteredModel
  }

  PanelWindow {
    screen: shellConfig.screen
    id: panel

    visible: surfaceTransition.presented
    color: "transparent"
    implicitHeight: 300

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:wallpaperPicker"
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: shell.open
      ? WlrKeyboardFocus.Exclusive
      : WlrKeyboardFocus.None

    anchors.left: true
    anchors.right: true
    anchors.bottom: true

    Item {
      id: launcher

      readonly property int padding: 16
      readonly property int searchHeight: 44
      readonly property int wallpaperWidth: 280
      readonly property int itemWidth: Math.round(wallpaperWidth * 0.84 + padding)
      readonly property int maxWallpapers: 9
      readonly property int visibleItems: {
        var fit = Math.max(1, Math.floor((panel.width - 84) / itemWidth));
        var visible = Math.min(fit, maxWallpapers, filteredModel.count);
        if (visible === 2)
          return 1;
        if (visible > 1 && visible % 2 === 0)
          return visible - 1;
        return visible;
      }
      readonly property int contentWidth: Math.max(520, Math.min(panel.width - 56, Math.max(1, visibleItems) * itemWidth))

      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 18
      width: contentWidth
      height: 250
      opacity: surfaceTransition.progress
      scale: 0.92 + surfaceTransition.progress * 0.08
      transformOrigin: Item.Bottom
      transform: Translate {
        y: (1 - surfaceTransition.progress) * 28
      }

      Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
          shell.cancel();
          event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          shell.commitCurrent();
          event.accepted = true;
        } else if (event.key === Qt.Key_Left || event.key === Qt.Key_H) {
          carousel.decrementCurrentIndex();
          event.accepted = true;
        } else if (event.key === Qt.Key_Right || event.key === Qt.Key_L) {
          carousel.incrementCurrentIndex();
          event.accepted = true;
        } else if (event.key === Qt.Key_Backspace && search.activeFocus && search.text.length === 0) {
          carousel.forceActiveFocus();
          event.accepted = true;
        } else if (event.text.length > 0 && !event.text.match(/[\r\n\t]/)) {
          search.forceActiveFocus();
          search.insert(search.cursorPosition, event.text);
          event.accepted = true;
        }
      }

      PathView {
        id: carousel

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: searchWrapper.y
        focus: true
        clip: true

        model: filteredModel
        pathItemCount: launcher.visibleItems
        cacheItemCount: 6
        snapMode: PathView.SnapToItem
        preferredHighlightBegin: 0.5
        preferredHighlightEnd: 0.5
        highlightRangeMode: PathView.StrictlyEnforceRange

        onCurrentIndexChanged: shell.previewCurrent()
        WheelHandler {
          acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
          onWheel: event => {
            if (event.angleDelta.y > 0)
              carousel.decrementCurrentIndex();
            else if (event.angleDelta.y < 0)
              carousel.incrementCurrentIndex();
            event.accepted = true;
          }
        }

        path: Path {
          startX: carousel.width * 0.08
          startY: carousel.height / 2 + 18

          PathAttribute { name: "tileScale"; value: 0.72 }
          PathAttribute { name: "tileZ"; value: 0 }
          PathAttribute { name: "shadeOpacity"; value: 0.28 }
          PathAttribute { name: "labelOpacity"; value: 0.42 }
          PathPercent { value: 0 }

          PathLine {
            x: carousel.width * 0.27
            y: carousel.height / 2 + 8
          }

          PathAttribute { name: "tileScale"; value: 0.84 }
          PathAttribute { name: "tileZ"; value: 2 }
          PathAttribute { name: "shadeOpacity"; value: 0.14 }
          PathAttribute { name: "labelOpacity"; value: 0.64 }
          PathPercent { value: 0.25 }

          PathLine {
            x: carousel.width / 2
            y: carousel.height / 2 - 4
          }

          PathAttribute { name: "tileScale"; value: 1.0 }
          PathAttribute { name: "tileZ"; value: 6 }
          PathAttribute { name: "shadeOpacity"; value: 0.0 }
          PathAttribute { name: "labelOpacity"; value: 1.0 }
          PathPercent { value: 0.5 }

          PathLine {
            x: carousel.width * 0.73
            y: carousel.height / 2 + 8
          }

          PathAttribute { name: "tileScale"; value: 0.84 }
          PathAttribute { name: "tileZ"; value: 2 }
          PathAttribute { name: "shadeOpacity"; value: 0.14 }
          PathAttribute { name: "labelOpacity"; value: 0.64 }
          PathPercent { value: 0.75 }

          PathLine {
            x: carousel.width * 0.92
            y: carousel.height / 2 + 18
          }

          PathAttribute { name: "tileScale"; value: 0.72 }
          PathAttribute { name: "tileZ"; value: 0 }
          PathAttribute { name: "shadeOpacity"; value: 0.28 }
          PathAttribute { name: "labelOpacity"; value: 0.42 }
          PathPercent { value: 1 }
        }

        delegate: Item {
          id: tile

          required property string path
          required property string name
          required property string relativePath
          required property int index

          width: launcher.itemWidth
          height: carousel.height
          z: PathView.tileZ ?? 0
          scale: PathView.onPath ? (PathView.tileScale ?? 0.72) : 0
          opacity: PathView.onPath ? 1 : 0

          Behavior on scale {
            MotionNumberAnimation { role: MotionNumberAnimation.FocusTravel }
          }

          Behavior on opacity {
            MotionNumberAnimation { role: MotionNumberAnimation.Content }
          }

          Rectangle {
            id: imageFrame

            anchors.horizontalCenter: parent.horizontalCenter
            y: 14
            width: launcher.wallpaperWidth
            height: Math.round(width / 16 * 9)
            radius: 10
            color: theme.surfaceMuted
            border.width: tile.PathView.isCurrentItem ? 1 : 0
            border.color: theme.borderSubtle
            clip: true

            Image {
              id: image
              anchors.fill: parent
              opacity: 1
              source: shell.imageUrl(tile.path)
              sourceSize.width: Math.max(1, Math.ceil(width * Screen.devicePixelRatio))
              sourceSize.height: Math.max(1, Math.ceil(height * Screen.devicePixelRatio))
              asynchronous: true
              fillMode: Image.PreserveAspectCrop
              smooth: !carousel.moving
            }

            Rectangle {
              anchors.fill: parent
              color: image.status === Image.Ready ? "transparent" : theme.surfaceMuted
              radius: imageFrame.radius
            }

            Rectangle {
              anchors.fill: parent
              radius: imageFrame.radius
              color: theme.bgSolid
              opacity: image.status === Image.Ready ? (tile.PathView.shadeOpacity ?? 0) : 0

              Behavior on opacity {
                MotionNumberAnimation { role: MotionNumberAnimation.Content }
              }
            }

            Text {
              anchors.centerIn: parent
              visible: image.status !== Image.Ready
              text: "󰋩"
              color: theme.mutedAlt
              font.family: theme.fontFamily
              font.pixelSize: 34
              font.bold: true
            }

            Rectangle {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              height: 38
              opacity: tile.PathView.isCurrentItem ? 0.82 : 0.38
              gradient: Gradient {
                GradientStop {
                  position: 0
                  color: "transparent"
                }
                GradientStop {
                  position: 1
                  color: theme.surfaceGlassStrong
                }
              }
            }
          }

          Rectangle {
            anchors.horizontalCenter: imageFrame.horizontalCenter
            anchors.top: imageFrame.bottom
            anchors.topMargin: 6
            width: tile.PathView.isCurrentItem ? Math.min(imageFrame.width - 24, 118) : 0
            height: 2
            radius: 1
            color: theme.blue
            opacity: tile.PathView.isCurrentItem ? 1 : 0

            Behavior on width {
              MotionNumberAnimation { role: MotionNumberAnimation.FocusTravel }
            }
          }

          Text {
            anchors.top: imageFrame.bottom
            anchors.topMargin: 12
            anchors.horizontalCenter: parent.horizontalCenter
            width: tile.PathView.isCurrentItem ? parent.width - 16 : imageFrame.width - 18
            text: tile.relativePath
            color: tile.PathView.isCurrentItem ? theme.foreground : theme.mutedAlt
            opacity: tile.PathView.labelOpacity ?? 0.45
            font.pointSize: 10
            font.weight: tile.PathView.isCurrentItem ? Font.Medium : Font.Normal
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideMiddle
            maximumLineCount: 1
            renderType: Text.QtRendering

            Behavior on opacity {
              MotionNumberAnimation { role: MotionNumberAnimation.FocusTravel }
            }
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              carousel.currentIndex = index;
              shell.commitCurrent();
            }
          }
        }
      }

      Rectangle {
        id: searchWrapper

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: launcher.searchHeight
        radius: 10
        color: theme.surfaceToast
        border.width: 1
        border.color: theme.borderSubtle

        Text {
          id: prefix

          anchors.left: parent.left
          anchors.leftMargin: launcher.padding
          anchors.verticalCenter: parent.verticalCenter
          text: "wallpaper"
          color: theme.terminalBlue
          font.pointSize: 11
          font.weight: Font.Medium
        }

        TextInput {
          id: search

          anchors.left: prefix.right
          anchors.leftMargin: 10
          anchors.right: parent.right
          anchors.rightMargin: launcher.padding
          anchors.verticalCenter: parent.verticalCenter
          color: theme.foreground
          selectionColor: theme.selectedBg
          selectedTextColor: theme.foreground
          font.pointSize: 11
          clip: true
          focus: false

          onTextChanged: shell.applyFilter()

          Keys.onEscapePressed: shell.cancel()
          Keys.onReturnPressed: shell.commitCurrent()
          Keys.onEnterPressed: shell.commitCurrent()
          Keys.onLeftPressed: {
            if (cursorPosition === 0) {
              carousel.decrementCurrentIndex();
              carousel.forceActiveFocus();
            }
          }
          Keys.onRightPressed: {
            if (cursorPosition === text.length) {
              carousel.incrementCurrentIndex();
              carousel.forceActiveFocus();
            }
          }
          Keys.onDownPressed: carousel.forceActiveFocus()
          Keys.onUpPressed: carousel.forceActiveFocus()
        }
      }

      Row {
        anchors.centerIn: carousel
        spacing: 14
        opacity: shell.ready && filteredModel.count === 0 ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
          MotionNumberAnimation { role: MotionNumberAnimation.Content }
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "No wallpapers found"
          color: theme.foreground
          font.pointSize: 15
          font.weight: Font.Medium
        }
      }
    }
  }
}
