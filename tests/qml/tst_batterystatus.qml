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
  function test_native_readings() {
    const data = { status: "Discharging", onBattery: true, changeRate: 6,
      timeToEmpty: 23940, lowPercentage: 25, criticalPercentage: 10, capacity: 12 };
    compare(BatteryStatus.severity(data), "low");
    const analysis = BatteryStatus.analysis(data, { bootWh: 0.1, bootSeconds: 60 });
    compare(analysis.estimateText, "6h 39m");
    compare(analysis.currentDraw, "6.0 W");
    compare(analysis.bootWh, 0.1);
    data.onBattery = false;
    data.status = "Not charging";
    compare(BatteryStatus.severity(data), "normal");
    compare(BatteryStatus.analysis(data, {}).estimateText, "plugged in");
    compare(BatteryStatus.analysis(data, {}).currentDraw, "--");
    data.onBattery = true;
    data.timeToEmpty = 0;
    compare(BatteryStatus.analysis(data, {}).estimateText, "--");
  }
}
