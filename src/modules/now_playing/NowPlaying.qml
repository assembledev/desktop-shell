import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import "../common"

Scope {
  id: root

  Theme {
    id: theme
  }

  ShellConfig { id: shellConfig }

  property var currentTrack: null
  property bool revealed: false
  property real playbackLength: 0
  readonly property int displayTimeout: 4200
  readonly property bool hasKnownLength: Number.isFinite(playbackLength) && playbackLength > 0
  readonly property bool hovered: lifetime.hovered
  readonly property string title: String(currentTrack?.title || "")
  readonly property string playerName: String(currentTrack?.playerName || "Media")
  readonly property string artwork: String(currentTrack?.artwork || "")
  readonly property string subtitle: {
    const artist = String(currentTrack?.artist || "").trim();
    const album = String(currentTrack?.album || "").trim();
    if (artist.length > 0 && album.length > 0 && artist !== album)
      return artist + "  ·  " + album;
    return artist || album || playerName;
  }
  readonly property color artworkTone: artworkPalette.colors[0] ?? theme.purple

  MotionTransition {
    id: surfaceTransition
    requested: root.revealed
    onDismissed: {
      if (!root.revealed)
        root.currentTrack = null;
    }
  }

  function formatTime(seconds) {
    if (!Number.isFinite(seconds) || seconds < 0)
      return "--:--";

    const total = Math.floor(seconds);
    const hours = Math.floor(total / 3600);
    const minutes = Math.floor((total % 3600) / 60);
    const secs = String(total % 60).padStart(2, "0");
    return hours > 0
      ? hours + ":" + String(minutes).padStart(2, "0") + ":" + secs
      : minutes + ":" + secs;
  }

  function updateLength(length) {
    playbackLength = Math.max(0, Number(length || 0));
  }

  function showTrack(track) {
    currentTrack = track;
    updateLength(track.length);
    revealed = true;
    lifetime.restart();
  }

  function updateTrack(track) {
    if (!currentTrack)
      return;
    const sameSourceTrack = currentTrack.sourceId === track.sourceId
      && currentTrack.trackKey === track.trackKey;
    const sameLogicalTrack = String(currentTrack.fingerprint || "").length > 0
      && currentTrack.fingerprint === track.fingerprint;
    if (!sameSourceTrack && !sameLogicalTrack)
      return;
    currentTrack = track;
    updateLength(track.length);
  }

  function hide() {
    if (!currentTrack)
      return;
    revealed = false;
    lifetime.stop();
  }

  MediaWatcher {
    onTrackChanged: function(track) {
      root.showTrack(track);
    }
    onTrackResumed: function(track) {
      root.showTrack(track);
    }
    onTrackUpdated: function(track) {
      root.updateTrack(track);
    }
  }

  ColorQuantizer {
    id: artworkPalette
    source: root.artwork
    depth: 0
    rescaleSize: 16
  }

  PanelWindow {
    screen: shellConfig.screen
    id: nowPlayingWindow
    visible: surfaceTransition.presented
    color: "transparent"
    exclusiveZone: 0
    implicitWidth: 372
    implicitHeight: 84
    WlrLayershell.namespace: "quickshell:nowPlaying"
    WlrLayershell.layer: WlrLayer.Overlay

    anchors {
      bottom: true
      right: true
    }

    margins {
      bottom: 28
      right: 22
    }

    mask: Region {
      item: card
    }

    ClippingRectangle {
      id: card
      anchors.fill: parent
      radius: 16
      color: theme.surfaceGlassStrong
      border.color: Qt.alpha(root.artworkTone, 0.54)
      border.width: 1
      contentUnderBorder: true
      opacity: surfaceTransition.progress
      scale: 0.92 + surfaceTransition.progress * 0.08
      transformOrigin: Item.BottomRight

      transform: Translate {
        x: (1 - surfaceTransition.progress) * 30
      }

      Behavior on border.color {
        MotionColorAnimation { role: MotionNumberAnimation.Content }
      }

      Rectangle {
        anchors.fill: parent
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0; color: Qt.alpha(root.artworkTone, 0.22) }
          GradientStop { position: 0.56; color: Qt.alpha(theme.purple, 0.06) }
          GradientStop { position: 1; color: Qt.alpha(theme.bgSolid, 0.12) }
        }
      }

      RowLayout {
        id: cardContent
        anchors.fill: parent
        anchors.margins: 10
        spacing: 13
        opacity: Math.max(0, Math.min(1, (surfaceTransition.progress - 0.14) / 0.86))
        transform: Translate {
          x: (1 - surfaceTransition.progress) * 10
        }

        ClippingRectangle {
          Layout.preferredWidth: 64
          Layout.preferredHeight: 64
          radius: 11
          color: Qt.alpha(theme.purple, 0.15)
          border.color: Qt.alpha(theme.foreground, 0.2)
          border.width: 1
          contentUnderBorder: true

          Image {
            id: artworkImage
            anchors.fill: parent
            source: root.artwork
            asynchronous: true
            cache: true
            fillMode: Image.PreserveAspectCrop
            visible: status === Image.Ready
          }

          Text {
            anchors.centerIn: parent
            visible: artworkImage.status !== Image.Ready
            text: "󰎈"
            color: theme.purple
            font.family: theme.fontFamily
            font.pixelSize: 26
          }
        }

        ColumnLayout {
          Layout.fillWidth: true
          Layout.fillHeight: true
          Layout.topMargin: 2
          Layout.bottomMargin: 2
          spacing: 2

          RowLayout {
            Layout.fillWidth: true
            spacing: 7

            Rectangle {
              Layout.preferredWidth: 16
              Layout.preferredHeight: 3
              radius: 2
              color: theme.purple
            }

            Text {
              text: "NOW PLAYING"
              color: theme.purple
              font.family: theme.fontFamily
              font.pixelSize: 9
              font.bold: true
              font.letterSpacing: 1
            }

            Rectangle {
              Layout.preferredWidth: 3
              Layout.preferredHeight: 3
              radius: 2
              color: theme.mutedAlt
            }

            Text {
              Layout.fillWidth: true
              text: root.playerName.toUpperCase()
              color: theme.mutedAlt
              font.family: theme.fontFamily
              font.pixelSize: 9
              elide: Text.ElideRight
            }

            Text {
              text: root.hasKnownLength ? root.formatTime(root.playbackLength) : "--:--"
              color: root.hovered ? theme.purple : theme.mutedAlt
              font.family: theme.fontFamily
              font.pixelSize: 9
              font.bold: root.hovered
            }
          }

          Text {
            Layout.fillWidth: true
            text: root.title
            color: theme.foreground
            font.family: theme.fontFamily
            font.pixelSize: 13
            font.bold: true
            elide: Text.ElideRight
          }

          Text {
            Layout.fillWidth: true
            text: root.subtitle
            color: theme.text
            font.family: theme.fontFamily
            font.pixelSize: 10
            elide: Text.ElideRight
          }
        }
      }

      ToastLifetimeBar {
        id: lifetime
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        duration: root.displayTimeout
        trackColor: Qt.alpha(theme.surfaceMuted, 0.72)
        accentColor: Qt.alpha(root.artworkTone, 0.86)
        hoverAccentColor: theme.purple
        onExpired: root.hide()
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: lifetime.pause()
        onExited: lifetime.resume()
        onClicked: root.hide()
      }
    }

  }
}
