import QtQuick
import QtQuick.Layouts
import "../common"

ColumnLayout {
  id: quick
  required property var controller
  required property var colors
  property bool compact: false
  spacing: 10
  component LevelRow: RowLayout {
    id: level
    property string glyph
    property string name
    property real value
    property real maximum: 1
    property bool available: true
    property bool muted: false
    property bool boostAllowed: false
    property bool muteControl: true
    signal moved(real value)
    signal toggleMute
    spacing: 8
    ShellSymbol {
      visible: !level.muteControl
      symbol: level.glyph
      tint: quick.colors.textSecondary
      size: 20
      Layout.preferredWidth: 30
    }
    ShellButton {
      visible: level.muteControl
      colors: quick.colors
      glyph: level.glyph
      accent: level.muted ? quick.colors.danger : quick.colors.info
      tooltip: (level.muted ? "Unmute " : "Mute ") + level.name
      flatAction: true
      implicitWidth: 30
      enabled: level.available
      onClicked: level.toggleMute()
    }
    ShellSlider {
      Layout.fillWidth: true
      colors: quick.colors
      from: 0
      to: level.maximum
      value: level.value
      boostAllowed: level.boostAllowed
      dimmed: level.muted
      enabled: level.available
      Accessible.name: level.name + " level"
      onMoved: level.moved(value)
    }
    Text {
      text: Math.round(level.value * 100) + "%"
      color: level.value > 1 ? quick.colors.caution : quick.colors.textSecondary
      font.family: quick.colors.uiFontFamily
      font.pixelSize: 10
      Layout.preferredWidth: 34
      horizontalAlignment: Text.AlignRight
    }
  }
  RowLayout {
    Layout.fillWidth: true
    spacing: 10
    ShellGroup {
      Layout.fillWidth: true
      Layout.preferredWidth: (quick.width - 10) / 2
      Layout.minimumWidth: 0
      colors: quick.colors
      implicitHeight: quick.compact ? 92 : 108
      ColumnLayout {
        anchors.fill: parent
        spacing: 0
        ConnectivityRow {
          Layout.fillWidth: true
          Layout.fillHeight: true
          colors: quick.colors
          title: "Wi-Fi"
          glyph: "wifi"
          subtitle: quick.controller.wifiSummaryText()
          active: quick.controller.wifiEnabled
          toggleEnabled: quick.controller.wifiToggleAvailable
          roundedBottom: false
          onToggleRequested: quick.controller.toggleWifi()
          onDetailRequested: quick.controller.page = "wifi"
        }
        ConnectivityRow {
          Layout.fillWidth: true
          Layout.fillHeight: true
          colors: quick.colors
          title: "Bluetooth"
          glyph: "bluetooth"
          accent: quick.colors.special
          subtitle: quick.controller.bluetoothSummaryText()
          active: quick.controller.bluetoothEnabled
          toggleEnabled: quick.controller.bluetoothStatusReady && quick.controller.bluetoothAvailable && !quick.controller.bluetoothBusy
          roundedTop: false
          onToggleRequested: quick.controller.toggleBluetooth()
          onDetailRequested: quick.controller.page = "bluetooth"
        }
      }
    }
    ColumnLayout {
      Layout.fillWidth: true
      Layout.preferredWidth: (quick.width - 10) / 2
      Layout.minimumWidth: 0
      spacing: 10
      ShellTaskButton {
        Layout.fillWidth: true
        colors: quick.colors
        surface: true
        cornerRadius: quick.colors.groupRadius
        implicitHeight: quick.compact ? 41 : 49
        title: "Do Not Disturb"
        glyph: "moon"
        subtitle: quick.controller.dnd ? "On" : "Off"
        active: quick.controller.dnd
        checkable: true
        checked: quick.controller.dnd
        onClicked: quick.controller.toggleDnd()
      }
      ShellTaskButton {
        Layout.fillWidth: true
        colors: quick.colors
        surface: true
        cornerRadius: quick.colors.groupRadius
        implicitHeight: quick.compact ? 41 : 49
        title: "Focus"
        glyph: "focus"
        subtitle: quick.controller.focusMode ? "On" : "Off"
        active: quick.controller.focusMode
        checkable: true
        checked: quick.controller.focusMode
        onClicked: quick.controller.setFocusMode(!quick.controller.focusMode)
      }
    }
  }
  ShellGroup {
    Layout.fillWidth: true
    colors: quick.colors
    implicitHeight: 74
    visible: quick.controller.brightnessSupported || quick.controller.displaysReady
    ColumnLayout {
      anchors.fill: parent
      spacing: 0
      ShellTaskButton {
        Layout.fillWidth: true
        colors: quick.colors
        title: "Display"
        navigation: true
        cornerRadius: quick.colors.groupRadius
        roundedBottom: false
        implicitHeight: 34
        onClicked: quick.controller.page = "display"
      }
      LevelRow {
        Layout.fillWidth: true
        Layout.leftMargin: 12
        Layout.rightMargin: 12
        Layout.bottomMargin: 10
        glyph: "sun"
        name: "Brightness"
        muteControl: false
        value: quick.controller.brightness
        available: quick.controller.brightnessSupported && quick.controller.brightnessWritable
        onMoved: value => quick.controller.setBrightness(value)
        visible: quick.controller.brightnessSupported
      }
    }
  }
  ShellGroup {
    Layout.fillWidth: true
    colors: quick.colors
    implicitHeight: quick.compact ? 74 : 104
    ColumnLayout {
      anchors.fill: parent
      spacing: 0
      ShellTaskButton {
        Layout.fillWidth: true
        colors: quick.colors
        title: "Sound"
        navigation: true
        cornerRadius: quick.colors.groupRadius
        roundedBottom: false
        implicitHeight: 34
        onClicked: quick.controller.page = "audio"
      }
      LevelRow {
        Layout.fillWidth: true
        Layout.leftMargin: 12
        Layout.rightMargin: 12
        Layout.bottomMargin: quick.compact ? 10 : 0
        glyph: quick.controller.sink?.audio?.muted ? "mute" : "speaker"
        name: "Output"
        value: quick.controller.sink?.audio?.volume || 0
        muted: quick.controller.sink?.audio?.muted || false
        available: !!quick.controller.sink?.audio
        onMoved: value => quick.controller.setNodeVolume(quick.controller.sink, value)
        onToggleMute: quick.controller.toggleNodeMute(quick.controller.sink)
      }
      LevelRow {
        Layout.fillWidth: true
        Layout.leftMargin: 12
        Layout.rightMargin: 12
        Layout.bottomMargin: 10
        visible: !quick.compact
        glyph: quick.controller.source?.audio?.muted ? "mic-off" : "mic"
        name: "Input"
        value: quick.controller.source?.audio?.volume || 0
        muted: quick.controller.source?.audio?.muted || false
        available: !!quick.controller.source?.audio
        onMoved: value => quick.controller.setNodeVolume(quick.controller.source, value)
        onToggleMute: quick.controller.toggleNodeMute(quick.controller.source)
      }
    }
  }
}
