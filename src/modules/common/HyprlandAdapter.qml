import QtQuick
import Quickshell.Hyprland

QtObject {
  function focusWorkspace(workspace) {
    Hyprland.dispatch("workspace " + Number(workspace));
  }

  function focusWindow(address) {
    Hyprland.dispatch("focuswindow address:" + String(address));
  }

  function focusDirection(direction) {
    Hyprland.dispatch("movefocus " + String(direction));
  }

  function moveWindowToWorkspace(address, workspace) {
    Hyprland.dispatch("movetoworkspacesilent " + Number(workspace) + ",address:" + String(address));
  }

  function swapWindow(address, targetAddress) {
    focusWindow(address);
    Hyprland.dispatch("swapwindow address:" + String(targetAddress));
  }

  function closeWindow(address) {
    Hyprland.dispatch("closewindow address:" + String(address));
  }
}
