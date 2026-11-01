import QtQuick
import Quickshell
import "modules/calendar"

ShellRoot {
  id: suite
  property int phase: 0
  property int ticks: 0

  PanelWindow {
    id: bar
    screen: Quickshell.screens[0]
    anchors { top: true; left: true; right: true }
    implicitHeight: 37
    exclusiveZone: 0
    color: "transparent"
  }
  CalendarPopup {
    id: calendar
    barSurface: bar
  }

  function verify(condition, message) {
    if (!condition) {
      console.error("FAIL calendar navigation: " + message);
      Qt.exit(1);
      throw new Error(message);
    }
  }
  function verifyMonth(month, year, message) {
    verify(calendar.viewMonth === month && calendar.viewYear === year,
      message + ": " + calendar.viewYear + "-" + (calendar.viewMonth + 1));
  }
  function verifyToday(message) {
    const today = new Date();
    verifyMonth(today.getMonth(), today.getFullYear(), message);
  }
  function burst(offset, count) {
    for (let i = 0; i < count; i++) {
      const next = new Date(calendar.viewYear, calendar.viewMonth + offset, 1);
      calendar.changeMonth(offset);
      verifyMonth(next.getMonth(), next.getFullYear(), "each input commits immediately");
    }
  }

  Timer {
    interval: 50
    running: true
    repeat: true
    onTriggered: {
      if (suite.phase === 0) {
        calendar.openCalendar(bar.screen);
        suite.verify(calendar.open, "open failed");
        suite.verifyToday("open returns to today");
        calendar.viewMonth = 10;
        calendar.viewYear = 2025;
        suite.burst(1, 5);
        suite.verifyMonth(3, 2026, "next burst crosses year boundary");
        suite.phase = 1;
      } else if (suite.phase === 1) {
        suite.burst(-1, 5);
        suite.verifyMonth(10, 2025, "previous burst reverses an active animation");
        suite.phase = 2;
      } else if (suite.phase === 2) {
        suite.burst(1, 2);
        suite.verifyMonth(0, 2026, "reversing again uses the latest logical month");
        suite.phase = 3;
        suite.ticks = 0;
      } else if (suite.phase === 3 && ++suite.ticks === 10) {
        suite.verifyMonth(0, 2026, "animation completion preserves the final input");
        calendar.changeMonth(1);
        calendar.resetToToday();
        suite.verifyToday("reset interrupts animation");
        suite.phase = 4;
      } else if (suite.phase === 4) {
        calendar.changeMonth(-2);
        calendar.closeCalendar();
        suite.verify(!calendar.open, "close interrupts animation");
        suite.phase = 5;
      } else if (suite.phase === 5) {
        calendar.openCalendar(bar.screen);
        suite.verify(calendar.open, "reopen failed");
        suite.verifyToday("reopen clears interrupted navigation");
        suite.phase = 6;
        suite.ticks = 0;
      } else if (suite.phase === 6 && ++suite.ticks === 10) {
        suite.verifyToday("old animation cannot overwrite reset/open");
        calendar.closeCalendar();
        console.log("PASS calendar navigation");
        Qt.quit();
      }
    }
  }
}
