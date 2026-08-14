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

  function desktopEntryIdIsValid(entryId) {
    return /^[A-Za-z0-9_.+-]+\.desktop$/.test(String(entryId || ""));
  }

  function launchDesktopEntry(entryId) {
    const fileId = String(entryId || "");
    if (!desktopEntryIdIsValid(fileId))
      return false;

    Hyprland.dispatch("hl.dsp.exec_cmd(" + luaString("uwsm app -- " + fileId) + ")");
    return true;
  }

  function launchDesktopEntryInWorkspace(entryId, workspace) {
    const fileId = String(entryId || "");
    const workspaceId = Number(workspace);
    if (!desktopEntryIdIsValid(fileId)
        || !Number.isInteger(workspaceId)
        || workspaceId <= 0)
      return false;

    Hyprland.dispatch("hl.dsp.exec_cmd("
                        + luaString("uwsm app -- " + fileId)
                        + ", { workspace = " + luaString(workspaceId + " silent")
                        + ", no_initial_focus = true })");
    return true;
  }

  function swapWindow(address, targetAddress) {
    focusWindow(address);
    Hyprland.dispatch("hl.dsp.window.swap({ target = " + luaString("address:" + targetAddress) + " })");
  }

  function closeWindow(address) {
    Hyprland.dispatch("hl.dsp.window.close({ window = " + luaString("address:" + address) + " })");
  }
}
