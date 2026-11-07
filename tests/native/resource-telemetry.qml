import QtQuick
import Quickshell
import Quickshell.Io
import "modules/bar"

ShellRoot {
  id: suite
  RamState { id: ram; path: Quickshell.env("RAM_FIXTURE"); interval: 100 }
  RamState { id: realRam; path: "/proc/meminfo"; active: true }
  VramState { id: gpu; backend: Quickshell.env("GPU_FIXTURE"); interval: 150 }
  IpcHandler {
    target: "test"
    function activate(ramVisible: bool, vramVisible: bool): void { ram.active = ramVisible; gpu.active = vramVisible; }
    function refresh(): void { ram.refresh(); gpu.refresh(); }
    function snapshot(): string { return JSON.stringify({ram:ram.data, gpu:gpu.data, real:realRam.data.available}); }
  }
}
