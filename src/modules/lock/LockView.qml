import QtQuick
import QtQuick.Effects
import QtQuick.Window
import "../common"

Item {
  id: root

  Theme {
    id: theme
  }

  property string wallpaperPath: ""
  property string clockText: ""
  property string dateText: ""
  property string userText: ""
  property string keyboardText: "--"
  property bool batteryVisible: false
  property string batteryText: ""
  property int passwordLength: 0
  property string message: ""
  property bool failed: false
  property bool authRunning: false

  readonly property color bg: theme.bgSolid
  readonly property color surface: theme.surfaceGlass
  readonly property color surfaceStrong: theme.surfaceGlassStrong
  readonly property color outline: failed ? theme.red : theme.borderSubtle
  readonly property color text: theme.foreground
  readonly property color muted: theme.mutedAlt
  readonly property color primary: theme.blue
  readonly property color secondary: theme.purple
  readonly property color warm: theme.yellow
  readonly property int fieldWidth: Math.min(580, Math.max(320, width - 64))

  signal appendText(string text)
  signal backspace(bool word)
  signal clear()
  signal submit()

  function fileUrl(path) {
    return path && path.length > 0 ? "file://" + encodeURI(path) : "";
  }

  function forceInputFocus() {
    keyCatcher.forceActiveFocus();
  }

  Rectangle {
    anchors.fill: parent
    color: root.bg

    Image {
      anchors.fill: parent
      source: root.fileUrl(root.wallpaperPath)
      sourceSize.width: Math.max(1, Math.ceil(width * Screen.devicePixelRatio))
      sourceSize.height: Math.max(1, Math.ceil(height * Screen.devicePixelRatio))
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      cache: true
      retainWhileLoading: true
    }

    Rectangle {
      anchors.fill: parent
      gradient: Gradient {
        orientation: Gradient.Vertical
        GradientStop { position: 0.0; color: Qt.alpha(theme.bgSolid, 0.76) }
        GradientStop { position: 0.42; color: Qt.alpha(theme.bgSolid, 0.48) }
        GradientStop { position: 1.0; color: Qt.alpha(theme.bgSolid, 0.88) }
      }
    }

    Rectangle {
      anchors.fill: parent
      color: theme.surfaceScrim
    }
  }

  MouseArea {
    id: keyCatcher

    anchors.fill: parent
    acceptedButtons: Qt.LeftButton
    focus: true
    hoverEnabled: true

    onPressed: forceActiveFocus()
    onPositionChanged: forceActiveFocus()

    Keys.onPressed: event => {
      if (root.authRunning) {
        event.accepted = true;
        return;
      }

      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        root.submit();
        event.accepted = true;
      } else if (event.key === Qt.Key_Backspace) {
        root.backspace((event.modifiers & Qt.ControlModifier) !== 0);
        event.accepted = true;
      } else if (event.key === Qt.Key_Escape) {
        root.clear();
        event.accepted = true;
      } else if (/^[^\x00-\x1F\x7F-\x9F]+$/.test(event.text)) {
        root.appendText(event.text);
        event.accepted = true;
      }
    }

    Row {
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.margins: 26
      spacing: 10

      StatusChip {
        compact: true
        icon: ""
        text: root.keyboardText
        accent: root.warm
      }

      StatusChip {
        visible: root.batteryVisible
        icon: ""
        text: root.batteryText
        accent: theme.green
      }
    }

    Column {
      id: center

      width: root.fieldWidth
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.verticalCenter: parent.verticalCenter
      anchors.verticalCenterOffset: -12
      spacing: 14

      Item {
        width: parent.width
        height: 258

        Column {
          anchors.centerIn: parent
          width: parent.width
          spacing: 8

          Text {
            width: parent.width
            text: root.clockText
            color: root.text
            font.family: theme.fontFamily
            font.pixelSize: Math.max(64, Math.min(116, root.width * 0.082))
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
          }

          Text {
            width: parent.width
            text: root.dateText
            color: root.warm
            font.family: theme.fontFamily
            font.pixelSize: Math.max(15, Math.min(22, root.width * 0.014))
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
          }

          Rectangle {
            width: 104
            height: 30
            radius: 15
            anchors.horizontalCenter: parent.horizontalCenter
            color: Qt.alpha(theme.surfaceGlassStrong, 0.64)
            border.color: Qt.alpha(theme.blue, 0.46)
            border.width: 1

            Row {
              anchors.centerIn: parent
              height: parent.height
              spacing: 7

              Text {
                height: parent.height
                text: ""
                color: root.primary
                font.family: theme.fontFamily
                font.pixelSize: 12
                font.bold: true
                verticalAlignment: Text.AlignVCenter
              }

              Text {
                height: parent.height
                text: root.userText
                color: theme.text
                font.family: theme.fontFamily
                font.pixelSize: 13
                font.bold: true
                verticalAlignment: Text.AlignVCenter
              }
            }
          }
        }
      }

      Rectangle {
        id: passwordField

        width: parent.width
        height: 70
        radius: height / 2
        anchors.horizontalCenter: parent.horizontalCenter
        color: Qt.alpha(root.surfaceStrong, 0.94)
        border.color: root.failed ? root.outline : Qt.alpha(theme.blue, 0.42)
        border.width: root.failed ? 2 : 1

        layer.enabled: true
        layer.effect: MultiEffect {
          shadowEnabled: true
          shadowColor: Qt.alpha(theme.bgSolid, 0.7)
          shadowBlur: 0.6
          shadowVerticalOffset: 8
        }

        Behavior on border.color { ColorAnimation { duration: 150 } }
        Behavior on border.width { NumberAnimation { duration: 110 } }

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton
          cursorShape: Qt.IBeamCursor
          onClicked: root.forceInputFocus()
        }

        Row {
          anchors.fill: parent
          anchors.leftMargin: 16
          anchors.rightMargin: 12
          spacing: 12

          Rectangle {
            width: 52
            height: 52
            radius: height / 2
            anchors.verticalCenter: parent.verticalCenter
            color: root.authRunning ? Qt.alpha(root.warm, 0.18) : Qt.alpha(root.primary, 0.18)

            LockGlyph {
              anchors.centerIn: parent
              active: root.authRunning
              color: root.authRunning ? root.warm : root.primary
            }
          }

          Item {
            id: inputArea

            width: parent.width - 52 - submitButton.width - 24
            height: parent.height
            anchors.verticalCenter: parent.verticalCenter
            clip: true

            Text {
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: parent.left
              anchors.right: parent.right
              text: {
                if (root.authRunning)
                  return "Checking...";
                if (root.message.length > 0)
                  return root.message;
                return "Enter password";
              }
              color: root.failed ? theme.red : (root.authRunning ? root.warm : root.muted)
              font.family: theme.fontFamily
              font.pixelSize: 16
              font.bold: true
              elide: Text.ElideRight
              opacity: root.passwordLength === 0 || root.authRunning || root.message.length > 0 ? 1 : 0

              Behavior on opacity { NumberAnimation { duration: 120 } }
            }

            Row {
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: parent.left
              spacing: 7
              visible: root.passwordLength > 0 && !root.authRunning && root.message.length === 0

              Repeater {
                model: Math.min(root.passwordLength, 32)

                Rectangle {
                  width: 9
                  height: 9
                  radius: 3
                  color: root.text
                  opacity: 0.88
                  scale: 1

                  Behavior on scale { NumberAnimation { duration: 90 } }
                }
              }

              Text {
                visible: root.passwordLength > 32
                text: "+"
                color: root.text
                font.family: theme.fontFamily
                font.pixelSize: 16
                font.bold: true
              }
            }
          }

          Rectangle {
            id: submitButton

            width: 54
            height: 54
            radius: height / 2
            anchors.verticalCenter: parent.verticalCenter
            color: root.passwordLength > 0 && !root.authRunning ? root.primary : theme.surfaceMuted

            Behavior on color { ColorAnimation { duration: 140 } }

            Text {
              anchors.centerIn: parent
              text: ""
              color: root.passwordLength > 0 && !root.authRunning ? root.bg : root.muted
              font.family: theme.fontFamily
              font.pixelSize: 20
              font.bold: true
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              enabled: root.passwordLength > 0 && !root.authRunning
              onClicked: root.submit()
            }
          }
        }
      }

      Text {
        width: parent.width
        height: 22
        text: root.failed && root.message.length === 0 ? "Wrong password" : ""
        color: theme.red
        font.family: theme.fontFamily
        font.pixelSize: 13
        font.bold: true
        horizontalAlignment: Text.AlignHCenter
        opacity: text.length > 0 ? 1 : 0

        Behavior on opacity { NumberAnimation { duration: 120 } }
      }
    }
  }

  component StatusChip: Rectangle {
    id: chip

    property string icon
    property string text
    property color accent
    property bool compact: false

    implicitWidth: compact ? 52 : chipRow.implicitWidth + 22
    implicitHeight: 38
    radius: implicitHeight / 2
    color: root.surface
    border.color: theme.borderSubtle
    border.width: 1

    Row {
      id: chipRow

      anchors.centerIn: parent
      spacing: 8

      Text {
        visible: chip.icon.length > 0
        width: visible ? 16 : 0
        height: chip.implicitHeight
        text: chip.icon
        color: chip.accent
        font.family: theme.fontFamily
        font.pixelSize: 15
        font.bold: true
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
      }

      Text {
        width: chip.compact ? chip.implicitWidth : implicitWidth
        height: chip.implicitHeight
        text: chip.text
        color: root.text
        font.family: theme.fontFamily
        font.pixelSize: 13
        font.bold: true
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
      }
    }
  }

  component LockGlyph: Item {
    id: glyph

    property bool active: false
    property color color: root.primary

    width: 24
    height: 26

    Item {
      anchors.fill: parent
      opacity: glyph.active ? 0 : 1

      Rectangle {
        width: 14
        height: 13
        radius: 7
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        color: "transparent"
        border.color: glyph.color
        border.width: 3
      }

      Rectangle {
        width: 19
        height: 16
        radius: 4
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        color: glyph.color
      }

      Rectangle {
        width: 3
        height: 6
        radius: 2
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 4
        color: root.bg
        opacity: 0.75
      }
    }

    Rectangle {
      width: 20
      height: 20
      radius: 10
      anchors.centerIn: parent
      visible: glyph.active
      color: "transparent"
      border.color: glyph.color
      border.width: 3
      opacity: 0.95

      SequentialAnimation on opacity {
        running: glyph.active
        loops: Animation.Infinite
        NumberAnimation { from: 0.38; to: 1; duration: 420; easing.type: Easing.InOutQuad }
        NumberAnimation { from: 1; to: 0.38; duration: 420; easing.type: Easing.InOutQuad }
      }
    }
  }
}
