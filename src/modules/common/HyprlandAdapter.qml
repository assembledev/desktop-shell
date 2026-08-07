import QtQuick
import Quickshell.Hyprland

QtObject {
  function luaString(value) {
    return '"' + String(value).replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"';
  }

  function focusWorkspace(workspace) {
    Hyprland.dispatch("hl.dsp.focus({ workspace = " + Number(workspace) + " })");
  }

  function focusWindow(address) {
    Hyprland.dispatch("hl.dsp.focus({ window = " + luaString("address:" + address) + " })");
  }

  function focusDirection(direction) {
    Hyprland.dispatch("hl.dsp.focus({ direction = " + luaString(direction) + " })");
  }

  function moveWindowToWorkspace(address, workspace) {
    Hyprland.dispatch("hl.dsp.window.move({ workspace = " + Number(workspace)
                        + ", follow = false, window = " + luaString("address:" + address) + " })");
  }

  function swapWindow(address, targetAddress) {
    focusWindow(address);
    Hyprland.dispatch("hl.dsp.window.swap({ target = " + luaString("address:" + targetAddress) + " })");
  }

  function closeWindow(address) {
    Hyprland.dispatch("hl.dsp.window.close({ window = " + luaString("address:" + address) + " })");
  }
}
