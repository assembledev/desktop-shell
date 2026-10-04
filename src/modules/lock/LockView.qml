import QtQuick
import QtQuick.Window
import "../common"
import "../bar"

Item {
  id: root

  Theme {
    id: theme
  }

  BarSpacing {
    id: statusSpacing
    compact: root.compactStatus
    portrait: root.width < root.height
  }

  property string wallpaperPath: ""
  property string clockText: ""
  property string dateText: ""
  property string userText: ""
  property string keyboardText: "--"
  property bool batteryVisible: false
  property string batteryText: ""
  property string batteryIcon: ""
  property string batterySeverity: "normal"
  property bool compactStatus: false
  property int passwordLength: 0
  property string message: ""
  property bool failed: false
  property bool authRunning: false
  property real entranceProgress: 0
  property real fieldShake: 0

  readonly property color bg: theme.bgSolid
  readonly property int fieldWidth: Math.max(0, Math.min(420, width - 48))

  signal appendText(string text)
  signal backspace(bool word)
  signal clear()
  signal submit()
  signal activity()

  Behavior on entranceProgress {
    MotionNumberAnimation { role: MotionNumberAnimation.SurfaceEnter }
  }

  Component.onCompleted: entranceProgress = 1

  onFailedChanged: {
    if (!failed)
      return;
    fieldShake = 6;
    fieldReturn.restart();
  }

  MotionNumberAnimation {
    id: fieldReturn
    target: root
    property: "fieldShake"
    to: 0
    role: MotionNumberAnimation.Expressive
  }

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
        GradientStop { position: 0.0; color: Qt.alpha(theme.bgSolid, 0.86) }
        GradientStop { position: 0.42; color: Qt.alpha(theme.bgSolid, 0.84) }
        GradientStop { position: 1.0; color: Qt.alpha(theme.bgSolid, 0.92) }
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

    onPressed: {
      root.activity();
      forceActiveFocus();
    }
    onPositionChanged: forceActiveFocus()

    Keys.onPressed: event => {
      root.activity();
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
      anchors.margins: 32
      spacing: 18
      opacity: root.entranceProgress

      Text {
        text: root.keyboardText
        color: theme.textSecondary
        font.family: theme.uiFontFamily
        font.pixelSize: 13
        height: 24
        verticalAlignment: Text.AlignVCenter
      }

      Rectangle {
        visible: root.batteryVisible
        width: 1
        height: 12
        anchors.verticalCenter: parent.verticalCenter
        color: theme.border
      }

      Row {
        visible: root.batteryVisible
        spacing: statusSpacing.contentGap
        height: 24

        Text {
          text: root.batteryIcon
          color: root.batterySeverity === "critical" ? theme.danger
            : root.batterySeverity === "low" ? theme.warning : theme.resource
          font.family: theme.fontFamily
          font.pixelSize: 15
          height: parent.height
          verticalAlignment: Text.AlignVCenter
        }

        Text {
          text: root.batteryText
          color: root.batterySeverity === "critical" ? theme.danger : theme.textSecondary
          font.family: theme.uiFontFamily
          font.pixelSize: 13
          height: parent.height
          verticalAlignment: Text.AlignVCenter
        }
      }
    }

    Column {
      width: root.fieldWidth
      anchors.centerIn: parent
      anchors.verticalCenterOffset: -12
      spacing: 12
      opacity: root.entranceProgress
      transform: Translate { y: (1 - root.entranceProgress) * 10 }

      Text {
        width: parent.width
        text: root.clockText
        color: theme.textPrimary
        font.family: theme.uiFontFamily
        font.pixelSize: Math.max(56, Math.min(96, root.width * 0.075))
        font.weight: Font.Normal
        horizontalAlignment: Text.AlignHCenter
      }

      Text {
        width: parent.width
        text: root.dateText
        color: theme.textSecondary
        font.family: theme.uiFontFamily
        font.pixelSize: 16
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
      }

      Item { width: 1; height: 24 }

      Text {
        width: parent.width
        text: root.userText
        color: theme.textMuted
        font.family: theme.uiFontFamily
        font.pixelSize: 13
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
      }

      Rectangle {
        id: passwordField
        width: parent.width
        height: 56
        radius: 10
        color: Qt.alpha(theme.bgRaised, 0.94)
        border.color: root.failed ? theme.danger : Qt.alpha(theme.accent, 0.45)
        border.width: 1
        transform: Translate { x: root.fieldShake }

        Behavior on border.color {
          MotionColorAnimation { role: MotionNumberAnimation.Feedback }
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.IBeamCursor
          onPressed: root.activity()
          onClicked: root.forceInputFocus()
        }

        Text {
          id: lockIcon
          anchors.left: parent.left
          anchors.leftMargin: 18
          anchors.verticalCenter: parent.verticalCenter
          text: ""
          color: root.failed ? theme.danger : theme.accent
          font.family: theme.fontFamily
          font.pixelSize: 16

          SequentialAnimation on opacity {
            running: root.authRunning
            loops: Animation.Infinite
            NumberAnimation { from: 1; to: 0.4; duration: 500 }
            NumberAnimation { from: 0.4; to: 1; duration: 500 }
            onRunningChanged: if (!running) lockIcon.opacity = 1
          }
        }

        Item {
          anchors.left: lockIcon.right
          anchors.leftMargin: 14
          anchors.right: submitButton.left
          anchors.rightMargin: 12
          height: parent.height
          clip: true

          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            text: root.authRunning ? "Checking…" : "Password"
            visible: root.passwordLength === 0 || root.authRunning
            color: theme.textMuted
            font.family: theme.uiFontFamily
            font.pixelSize: 15
            elide: Text.ElideRight
          }

          Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            visible: root.passwordLength > 0 && !root.authRunning

            Repeater {
              model: Math.min(root.passwordLength, 24)
              Rectangle {
                width: 5
                height: 5
                radius: 2.5
                color: theme.textPrimary
              }
            }

            Text {
              visible: root.passwordLength > 24
              text: "+"
              color: theme.textPrimary
              font.family: theme.uiFontFamily
              font.pixelSize: 12
              anchors.verticalCenter: parent.verticalCenter
            }
          }
        }

        Rectangle {
          id: submitButton
          anchors.right: parent.right
          anchors.rightMargin: 10
          anchors.verticalCenter: parent.verticalCenter
          width: 36
          height: 36
          radius: 6
          color: submitMouse.containsMouse && submitMouse.enabled ? theme.surfaceHover : "transparent"

          Text {
            anchors.centerIn: parent
            text: ""
            color: submitMouse.enabled ? theme.accent : theme.textMuted
            font.family: theme.fontFamily
            font.pixelSize: 16
          }

          MouseArea {
            id: submitMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            enabled: root.passwordLength > 0 && !root.authRunning
            onPressed: root.activity()
            onClicked: root.submit()
          }
        }
      }

      Text {
        width: parent.width
        height: 40
        text: root.authRunning ? "" : (root.message || (root.failed ? "Wrong password" : ""))
        color: root.failed ? theme.danger : theme.textMuted
        font.family: theme.uiFontFamily
        font.pixelSize: 13
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
      }
    }
  }
}
