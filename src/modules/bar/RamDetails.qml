import QtQuick
import QtQuick.Layouts
import "RamStatus.js" as RamStatus

Item {
  id: card
  required property var colors
  required property var details
  required property var processes
  signal copyPid(string pid)
  readonly property real usedFraction: details ? details.usedKiB / details.totalKiB : 0
  readonly property real reclaimableKiB: details?.reclaimableKiB ?? 0
  readonly property var swap: details?.swap ?? null
  readonly property int padding: 14

  implicitHeight: content.implicitHeight + 2 * padding

  ColumnLayout {
    id: content
    x: card.padding
    y: card.padding
    width: card.width - 2 * card.padding
    spacing: 9

    RowLayout {
      spacing: 7

      DetailText {
        text: "󰟜"
        color: card.colors.resource
        font.family: card.colors.fontFamily
        font.pixelSize: 16
      }

      DetailText {
        Layout.fillWidth: true
        text: "RAM"
        font.weight: Font.DemiBold
      }
    }

    DetailText {
      visible: card.details === null
      text: "Memory data unavailable"
      color: card.colors.textSecondary
    }

    RowLayout {
      visible: card.details !== null
      spacing: 6

      DetailText {
        Layout.alignment: Qt.AlignBaseline
        text: card.details ? RamStatus.formatAmount(card.details.usedKiB) : ""
        font.pixelSize: 12
        font.weight: Font.DemiBold
      }

      DetailText {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignBaseline
        text: card.details ? "/ " + RamStatus.formatAmount(card.details.totalKiB) : ""
        color: card.colors.textMuted
        font.pixelSize: 12
      }
    }

    Rectangle {
      id: ramMeter
      visible: card.details !== null
      Layout.fillWidth: true
      implicitHeight: 5
      radius: height / 2
      color: card.colors.borderMuted

      Rectangle {
        visible: card.reclaimableKiB > 0
        width: card.details ? ramMeter.width * (card.details.usedKiB + card.reclaimableKiB) / card.details.totalKiB : 0
        height: ramMeter.height
        radius: ramMeter.radius
        color: Qt.alpha(card.colors.resource, 0.38)
      }

      Rectangle {
        width: ramMeter.width * card.usedFraction
        height: ramMeter.height
        radius: ramMeter.radius
        color: card.colors.resource
      }
    }

    DetailText {
      visible: card.reclaimableKiB > 0
      text: "≈" + RamStatus.formatAmount(card.reclaimableKiB) + " reclaimable"
      color: card.colors.textMuted
      font.pixelSize: 12
    }

    ColumnLayout {
      spacing: 6

      Divider {}

      ProcessRow {
        heading: true
        nameText: "Top processes"
        pidText: "PID"
        memoryText: "RAM (RSS)"
      }

      Repeater {
        model: 3
        ProcessRow {
          required property int index
          readonly property var sample: card.processes?.[index] ?? null
          placeholder: sample === null
          nameText: {
            if (sample) return sample.name;
            if (index !== 0) return " ";
            return card.processes === null ? "Reading processes…" : "Process data unavailable";
          }
          pidText: sample ? String(sample.pid) : ""
          memoryText: sample ? RamStatus.formatAmount(sample.rssKiB) : ""
        }
      }
    }

    ColumnLayout {
      visible: card.swap !== null
      spacing: 6

      Divider {}

      RowLayout {
        DetailText {
          Layout.fillWidth: true
          text: "Swap"
          color: card.colors.textMuted
          font.pixelSize: 12
        }

        DetailText {
          text: {
            if (!card.swap) return "";
            const total = RamStatus.formatAmount(card.swap.totalKiB);
            return card.swap.usedKiB > 0 ? RamStatus.formatAmount(card.swap.usedKiB) + " / " + total : total + " unused";
          }
          color: card.colors.textSecondary
          font.pixelSize: 12
        }
      }
    }
  }

  component DetailText: Text {
    color: card.colors.textPrimary
    font.family: card.colors.uiFontFamily
    font.pixelSize: 13
    font.features: ({ tnum: 1 })
    textFormat: Text.PlainText
  }

  component Divider: Rectangle {
    Layout.fillWidth: true
    implicitHeight: 1
    color: card.colors.borderSubtle
  }

  component ProcessRow: RowLayout {
    id: row
    required property string nameText
    required property string pidText
    required property string memoryText
    property bool heading: false
    property bool placeholder: false

    DetailText {
      Layout.fillWidth: true
      Layout.minimumWidth: 0
      text: row.nameText
      elide: Text.ElideRight
      color: row.placeholder ? card.colors.textMuted : card.colors.textSecondary
      font.weight: row.heading ? Font.DemiBold : Font.Normal
    }

    DetailText {
      visible: !row.placeholder
      Layout.preferredWidth: 50
      horizontalAlignment: Text.AlignRight
      text: row.pidText
      color: pidButton.containsMouse ? card.colors.accent : card.colors.textMuted
      font.pixelSize: 11
      font.underline: pidButton.containsMouse

      MouseArea {
        id: pidButton
        objectName: "copyPid" + row.pidText
        anchors.fill: parent
        enabled: !row.heading && !row.placeholder
        visible: enabled
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        Accessible.role: Accessible.Button
        Accessible.name: "Copy PID " + row.pidText
        Accessible.onPressAction: card.copyPid(row.pidText)
        onClicked: card.copyPid(row.pidText)
      }
    }

    DetailText {
      visible: !row.placeholder
      Layout.preferredWidth: 68
      horizontalAlignment: Text.AlignRight
      text: row.memoryText
      color: row.heading ? card.colors.textMuted : card.colors.textPrimary
      font.pixelSize: row.heading ? 11 : 12
    }
  }
}
