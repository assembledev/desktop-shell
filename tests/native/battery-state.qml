import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import "modules/common"

ShellRoot {
  id: suite
  property bool recording: true
  BatteryState { id: battery; statistics: historyLoader.item?.data || ({}) }
  Loader {
    id: historyLoader
    active: suite.recording
    sourceComponent: BatteryHistory { sample: battery.telemetry }
  }
  BatteryState { id: locker }
  IpcHandler {
    target: "fixture"
    function stopRecording(): void { suite.recording = false; }
    function state(): string {
      return JSON.stringify({ ready: UPower.displayDevice.ready, data: battery.data, lockData: locker.data });
    }
  }
}
