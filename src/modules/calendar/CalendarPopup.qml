pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../common"

Scope {
  id: root

  Theme {
    id: theme
  }

  ShellConfig { id: shellConfig }
  MotionTransition {
    id: surfaceTransition
    requested: root.open
  }

  property bool open: false
  property date today: new Date()
  property int viewMonth: today.getMonth()
  property int viewYear: today.getFullYear()
  property int pendingMonth: viewMonth
  property int pendingYear: viewYear
  property int monthDirection: 1
  readonly property bool currentMonth: viewMonth === today.getMonth() && viewYear === today.getFullYear()
  readonly property bool portraitMode: Number(window.screen?.width || 0) > 0 && Number(window.screen?.width || 0) < Number(window.screen?.height || 0)

  function resetToToday() {
    today = new Date();
    showMonth(today.getMonth(), today.getFullYear());
  }

  function changeMonth(offset) {
    const next = new Date(viewYear, viewMonth + offset, 1);
    showMonth(next.getMonth(), next.getFullYear(), offset < 0 ? -1 : 1);
  }

  function showMonth(month, year, direction) {
    if (month === viewMonth && year === viewYear)
      return;

    pendingMonth = month;
    pendingYear = year;
    monthDirection = direction || ((year * 12 + month) < (viewYear * 12 + viewMonth) ? -1 : 1);
    if (!open) {
      viewMonth = pendingMonth;
      viewYear = pendingYear;
      return;
    }

    monthTransition.restart();
  }

  function openCalendar() {
    resetToToday();
    open = true;
    Qt.callLater(function () {
      focusLayer.forceActiveFocus();
    });
  }

  function closeCalendar() {
    open = false;
  }

  function toggleCalendar() {
    if (open)
      closeCalendar();
    else
      openCalendar();
  }

  function refreshToday() {
    const previous = today;
    const followingToday = viewMonth === previous.getMonth() && viewYear === previous.getFullYear();
    today = new Date();
    if (followingToday) {
      viewMonth = today.getMonth();
      viewYear = today.getFullYear();
    }
  }

  IpcHandler {
    target: "calendar"
    function open(): void {
      root.openCalendar();
    }
    function close(): void {
      root.closeCalendar();
    }
    function toggle(): void {
      root.toggleCalendar();
    }
  }

  Timer {
    interval: 60000
    running: true
    repeat: true
    onTriggered: root.refreshToday()
  }

  SequentialAnimation {
    id: monthTransition

    ParallelAnimation {
      MotionNumberAnimation {
        target: calendarGrid
        property: "opacity"
        to: 0
        role: MotionNumberAnimation.SurfaceExit
      }
      MotionNumberAnimation {
        target: calendarGrid
        property: "x"
        to: -root.monthDirection * 18
        role: MotionNumberAnimation.SurfaceExit
      }
    }
    ScriptAction {
      script: {
        root.viewMonth = root.pendingMonth;
        root.viewYear = root.pendingYear;
        calendarGrid.x = root.monthDirection * 18;
      }
    }
    ParallelAnimation {
      MotionNumberAnimation {
        target: calendarGrid
        property: "opacity"
        to: 1
        role: MotionNumberAnimation.Content
      }
      MotionNumberAnimation {
        target: calendarGrid
        property: "x"
        to: 0
        role: MotionNumberAnimation.Content
      }
    }
  }

  PanelWindow {
    screen: shellConfig.screen
    id: window

    visible: surfaceTransition.presented
    color: "transparent"
    exclusiveZone: 0

    WlrLayershell.namespace: "quickshell:calendar"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.open
      ? WlrKeyboardFocus.OnDemand
      : WlrKeyboardFocus.None

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    Item {
      id: inputLayer
      anchors.fill: parent

      MouseArea {
        anchors.fill: parent
        enabled: root.open
        onClicked: root.closeCalendar()
      }

      FocusScope {
        id: focusLayer
        anchors.fill: parent
        focus: root.open

        Shortcut {
          enabled: root.open
          sequence: "Esc"
          onActivated: root.closeCalendar()
        }

        Shortcut {
          enabled: root.open
          sequence: "Left"
          onActivated: root.changeMonth(-1)
        }

        Shortcut {
          enabled: root.open
          sequence: "Right"
          onActivated: root.changeMonth(1)
        }

        Shortcut {
          enabled: root.open
          sequence: "Home"
          onActivated: root.resetToToday()
        }

        Rectangle {
          id: panel

          width: Math.min(390, window.width - 24)
          height: content.implicitHeight + 32
          anchors.top: parent.top
          anchors.topMargin: root.portraitMode ? 90 : 39
          anchors.horizontalCenter: parent.horizontalCenter
          radius: 14
          color: Qt.alpha(theme.bgSolid, 0.86)
          border.color: Qt.alpha(theme.borderSubtle, 0.72)
          border.width: 1
          clip: true
          opacity: surfaceTransition.progress
          scale: 0.92 + surfaceTransition.progress * 0.08
          transformOrigin: Item.Top
          transform: Translate {
            y: (1 - surfaceTransition.progress) * -12
          }

          MouseArea {
            anchors.fill: parent
            onClicked: function (mouse) {
              mouse.accepted = true;
            }
          }

          ColumnLayout {
            id: content

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 16
            spacing: 14
            opacity: Math.max(0, Math.min(1, (surfaceTransition.progress - 0.14) / 0.86))

            ColumnLayout {
              Layout.fillWidth: true
              spacing: 2

              Text {
                Layout.fillWidth: true
                text: Qt.formatDate(root.today, "dddd").toUpperCase()
                color: theme.yellow
                font.family: theme.fontFamily
                font.pixelSize: 11
                font.bold: true
                elide: Text.ElideRight
              }

              Text {
                Layout.fillWidth: true
                text: Qt.formatDate(root.today, "d MMMM yyyy")
                color: theme.foreground
                font.family: theme.fontFamily
                font.pixelSize: 22
                font.bold: true
                elide: Text.ElideRight
              }
            }

            Rectangle {
              Layout.fillWidth: true
              Layout.preferredHeight: 1
              color: Qt.alpha(theme.borderSubtle, 0.72)
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: 8

              CalendarButton {
                icon: ""
                tooltip: "Previous month"
                onClicked: root.changeMonth(-1)
              }

              Text {
                Layout.fillWidth: true
                text: Qt.formatDate(new Date(root.viewYear, root.viewMonth, 1), "MMMM yyyy")
                color: theme.text
                font.family: theme.fontFamily
                font.pixelSize: 15
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight

                MouseArea {
                  anchors.fill: parent
                  enabled: !root.currentMonth
                  cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                  onClicked: root.resetToToday()
                }
              }

              CalendarButton {
                icon: ""
                tooltip: "Next month"
                onClicked: root.changeMonth(1)
              }
            }

            GridLayout {
              id: calendarGrid
              Layout.fillWidth: true
              Layout.preferredHeight: 262
              columns: 2
              columnSpacing: 6
              rowSpacing: 4

              Text {
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                text: "#"
                color: theme.muted
                opacity: 0.72
                font.family: theme.fontFamily
                font.pixelSize: 9
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
              }

              DayOfWeekRow {
                id: weekDays

                Layout.fillWidth: true
                Layout.preferredHeight: 24
                locale: Qt.locale()
                spacing: 0

                delegate: Text {
                  required property string narrowName

                  text: narrowName.toUpperCase()
                  color: theme.mutedAlt
                  font.family: theme.fontFamily
                  font.pixelSize: 10
                  font.bold: true
                  horizontalAlignment: Text.AlignHCenter
                  verticalAlignment: Text.AlignVCenter
                }
              }

              WeekNumberColumn {
                Layout.preferredWidth: 24
                Layout.fillHeight: true
                month: root.viewMonth
                year: root.viewYear
                locale: weekDays.locale

                delegate: Text {
                  required property int weekNumber

                  text: weekNumber
                  color: theme.muted
                  opacity: 0.72
                  font.family: theme.fontFamily
                  font.pixelSize: 9
                  font.bold: true
                  horizontalAlignment: Text.AlignHCenter
                  verticalAlignment: Text.AlignVCenter
                }
              }

              MonthGrid {
                id: monthGrid

                Layout.fillWidth: true
                Layout.fillHeight: true
                month: root.viewMonth
                year: root.viewYear
                locale: weekDays.locale
                spacing: 0

                delegate: Item {
                  id: dayCell

                  required property var model
                  readonly property bool isToday: dayCell.model.day === root.today.getDate()
                    && dayCell.model.month === root.today.getMonth()
                    && dayCell.model.year === root.today.getFullYear()

                  opacity: dayCell.model.month === root.viewMonth ? 1 : 0.34

                  Rectangle {
                    anchors.centerIn: parent
                    width: 30
                    height: 30
                    radius: 9
                    color: dayCell.isToday ? theme.blue : "transparent"

                    Text {
                      anchors.centerIn: parent
                      text: dayCell.model.day
                      color: dayCell.isToday ? theme.bgSolid : theme.text
                      font.family: theme.fontFamily
                      font.pixelSize: 12
                      font.bold: dayCell.isToday
                      horizontalAlignment: Text.AlignHCenter
                      verticalAlignment: Text.AlignVCenter
                    }
                  }
                }
              }
            }

            Text {
              Layout.alignment: Qt.AlignHCenter
              Layout.preferredHeight: 12
              text: "Return to today"
              color: theme.blue
              opacity: root.currentMonth ? 0 : 1
              font.family: theme.fontFamily
              font.pixelSize: 10
              font.bold: true

              MouseArea {
                anchors.fill: parent
                anchors.margins: -8
                enabled: !root.currentMonth
                cursorShape: Qt.PointingHandCursor
                onClicked: root.resetToToday()
              }
            }
          }
        }
      }
    }
  }

  component CalendarButton: Rectangle {
    id: button

    required property string icon
    property string tooltip: ""
    signal clicked

    Layout.preferredWidth: 34
    Layout.preferredHeight: 30
    radius: 9
    color: mouse.containsMouse ? theme.surfaceHover : theme.surfaceMuted
    border.color: mouse.containsMouse ? theme.blue : theme.borderMuted
    border.width: 1
    scale: mouse.pressed ? 0.92 : 1

    Behavior on color {
      MotionColorAnimation { role: MotionNumberAnimation.Feedback }
    }
    Behavior on scale {
      MotionNumberAnimation { role: MotionNumberAnimation.Feedback }
    }

    Text {
      anchors.centerIn: parent
      text: button.icon
      color: mouse.containsMouse ? theme.blue : theme.mutedAlt
      font.family: theme.fontFamily
      font.pixelSize: 11
      font.bold: true
    }

    MouseArea {
      id: mouse

      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: button.clicked()
    }

    ToolTip.visible: mouse.containsMouse && button.tooltip.length > 0
    ToolTip.text: button.tooltip
    ToolTip.delay: 500
  }
}
