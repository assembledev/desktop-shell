import QtQuick
import QtTest
import "../../src/modules/common/BatteryStatus.js" as BatteryStatus

TestCase {
  name: "BatteryStatus"

  function test_charge_thresholds_data() {
    return [
      { tag: "empty", capacity: 0, status: "Discharging", severity: "critical", icon: "󰁺" },
      { tag: "critical", capacity: 15, status: "Discharging", severity: "critical", icon: "󰁻" },
      { tag: "low", capacity: 30, status: "Discharging", severity: "low", icon: "󰁽" },
      { tag: "normal", capacity: 31, status: "Discharging", severity: "normal", icon: "󰁽" },
      { tag: "charging", capacity: 5, status: "Charging", severity: "normal", icon: "󰂄" },
      { tag: "full", capacity: 100, status: "Full", severity: "normal", icon: "󰁹" }
    ];
  }

  function test_charge_thresholds(data) {
    compare(BatteryStatus.severity(data), data.severity);
    compare(BatteryStatus.icon(data), data.icon);
  }

  function test_capacity_sanitization() {
    compare(BatteryStatus.capacity({ capacity: 110 }), 100);
    compare(BatteryStatus.capacity({ capacity: -10 }), 0);
    compare(BatteryStatus.capacity({ capacity: "bad" }), 0);
    compare(BatteryStatus.capacity({ capacity: 44.6 }), 45);
  }
}
