pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../common"

Scope {
  id: root
  property var taskHost: null
  function cancelTask() { closeCalendar(); }
  onOpenChanged: { if (!open && taskHost) taskHost.releaseTask(root); }

  property Item popupAnchor: null
  required property var barSurface
  readonly property var screen: placement.screen

  Theme {
    id: theme
  }

  ShellConfig { id: shellConfig }
  ScreenPlacement {
    id: placement
    configuration: shellConfig
    onRemoved: root.closeCalendar()
  }
  MotionTransition {
    id: surfaceTransition
    requested: root.open
  }

  property bool open: false
  property date today: new Date()
  property int viewMonth: today.getMonth()
  property int viewYear: today.getFullYear()
  property int monthDirection: 1
  readonly property bool currentMonth: viewMonth === today.getMonth() && viewYear === today.getFullYear()
  readonly property bool portraitMode: Number(window.screen?.width || 0) > 0 && Number(window.screen?.width || 0) < Number(window.screen?.height || 0)

  function resetToToday() {
    monthTransition.stop();
    calendarGrid.x = 0;
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

    monthDirection = direction || ((year * 12 + month) < (viewYear * 12 + viewMonth) ? -1 : 1);
    // Update immediately so repeated input uses the latest month.
    viewMonth = month;
    viewYear = year;
    if (open)
      monthTransition.restart();
  }

  function openCalendar(screen, trigger) {
    if (!placement.capture(screen))
      return;
    if (taskHost)
      taskHost.requestTask(root, placement.screen);
    popupAnchor = trigger || barSurface?.popupTrigger?.("calendar") || null;
    window.keyboardRequested = screen === undefined;
    resetToToday();
    open = true;
    if (window.keyboardRequested)
      Qt.callLater(() => { if (root.open && window.keyboardRequested) previousMonth.forceActiveFocus(Qt.TabFocusReason); });
  }

  function closeCalendar() {
    monthTransition.stop();
    open = false;
  }

  function toggleCalendar(screen, trigger) {
    if (open && placement.matches(screen))
      closeCalendar();
    else
      openCalendar(screen, trigger);
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

  MotionNumberAnimation {
    id: monthTransition
    target: calendarGrid
    property: "x"
    from: root.monthDirection * 18
    to: 0
    role: MotionNumberAnimation.Content
  }

  BarPopupPlacement {
    id: popupPlacement
    trigger: root.popupAnchor
    screenWidth: root.screen?.width || 0
    screenHeight: root.screen?.height || 0
    barHeight: root.barSurface?.height || 0
    preferredWidth: 390
    gap: theme.barPopoverGap
    active: root.open
    onAnchorLost: root.closeCalendar()
  }

  BarOverlayWindow {
    id: window
    barSurface: root.barSurface
    targetScreen: placement.screen
    requested: root.open
    presented: surfaceTransition.presented
    surfaceNamespace: "quickshell:calendar"

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

          width: popupPlacement.width
          height: Math.min(content.implicitHeight + 32, popupPlacement.maximumHeight)
          x: popupPlacement.x
          y: popupPlacement.y
          radius: 14
          color: Qt.alpha(theme.bgSolid, 0.86)
          border.color: theme.borderSubtle
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

          Flickable {
            anchors.fill: parent
            contentWidth: width
            contentHeight: content.implicitHeight + 32
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            ColumnLayout {
              id: content

              x: 16
              y: 16
              width: parent.width - 32
              spacing: 14
              opacity: Math.max(0, Math.min(1, (surfaceTransition.progress - 0.14) / 0.86))

              ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                  Layout.fillWidth: true
                  text: Qt.formatDate(root.today, "dddd").toUpperCase()
                  color: theme.utility
                  font.family: theme.uiFontFamily
                  font.pixelSize: 11
                  font.bold: true
                  elide: Text.ElideRight
                }

                Text {
                  Layout.fillWidth: true
                  text: Qt.formatDate(root.today, "d MMMM yyyy")
                  color: theme.textPrimary
                  font.family: theme.uiFontFamily
                  font.pixelSize: 22
                  font.bold: true
                  elide: Text.ElideRight
                }
              }

              Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: theme.borderSubtle
              }

              RowLayout {
                Layout.fillWidth: true
                spacing: 8

                CalendarButton {
                  id: previousMonth
                  glyph: "back"
                  tooltip: "Previous month"
                  onClicked: root.changeMonth(-1)
                }

                Text {
                  Layout.fillWidth: true
                  text: Qt.formatDate(new Date(root.viewYear, root.viewMonth, 1), "MMMM yyyy")
                  color: theme.textSecondary
                  font.family: theme.uiFontFamily
                  font.pixelSize: 15
                  font.bold: true
                  horizontalAlignment: Text.AlignHCenter
                  elide: Text.ElideRight
                }

                CalendarButton {
                  glyph: "right"
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
                  color: theme.textMuted
                  font.family: theme.uiFontFamily
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
                    color: theme.textMuted
                    font.family: theme.uiFontFamily
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
                    color: theme.textMuted
                    font.family: theme.uiFontFamily
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
                      color: dayCell.isToday ? theme.accent : "transparent"

                      Text {
                        anchors.centerIn: parent
                        text: dayCell.model.day
                        color: dayCell.isToday ? theme.textOnAccent : theme.textSecondary
                        font.family: theme.uiFontFamily
                        font.pixelSize: 12
                        font.bold: dayCell.isToday
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                      }
                    }
                  }
                }
              }

              ShellButton {
                colors: theme
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredHeight: 20
                label: "Return to today"
                enabled: !root.currentMonth
                opacity: root.currentMonth ? 0 : 1
                flatAction: true
                verticalPadding: 2
                Keys.onReturnPressed: click()
                Keys.onEnterPressed: click()
                onClicked: root.resetToToday()
              }
            }
          }
        }
      }
    }
  }

  component CalendarButton: ShellButton {
    colors: theme
    Layout.preferredWidth: 34
    Layout.preferredHeight: 30
    Keys.onReturnPressed: click()
    Keys.onEnterPressed: click()
  }
}
