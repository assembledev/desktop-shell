import QtQuick
import Quickshell
import Quickshell.Services.UPower
import "BatteryStatus.js" as BatteryStatus

Scope {
  id: root

  property var statistics: ({})
  property int lowPercentage: Number(Quickshell.env("DESKTOP_SHELL_BATTERY_LOW") || 30)
  property int criticalPercentage: Number(Quickshell.env("DESKTOP_SHELL_BATTERY_CRITICAL") || 15)
  readonly property UPowerDevice device: UPower.displayDevice
  readonly property bool available: device.ready && device.isLaptopBattery && device.isPresent
  readonly property var telemetry: ({
    available: available,
    capacity: available ? Math.round(device.percentage * 100) : 0,
    status: powerStatus(),
    onBattery: UPower.onBattery,
    energy: available ? device.energy : 0,
    changeRate: available ? Math.abs(device.changeRate) : 0,
    timeToEmpty: available ? device.timeToEmpty : 0,
    power: available ? Math.abs(device.changeRate).toFixed(1) + "W" : "",
    lowPercentage: lowPercentage,
    criticalPercentage: criticalPercentage
  })
  readonly property var data: Object.assign({}, telemetry, {
    analysis: BatteryStatus.analysis(telemetry, statistics)
  })
  readonly property string icon: BatteryStatus.icon(data)
  readonly property string label: BatteryStatus.capacity(data) + "%"
  readonly property string severity: BatteryStatus.severity(data)

  function powerStatus() {
    if (!available)
      return "";
    switch (device.state) {
    case UPowerDeviceState.Charging: return "Charging";
    case UPowerDeviceState.FullyCharged: return "Full";
    case UPowerDeviceState.PendingCharge: return "Not charging";
    case UPowerDeviceState.Discharging:
    case UPowerDeviceState.Empty:
    case UPowerDeviceState.PendingDischarge: return "Discharging";
    default: return "Unknown";
    }
  }

}
