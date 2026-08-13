.pragma library

function normalizedAddress(value) {
  // Hyprland IPC JSON includes 0x, while Quickshell's toplevel property omits it.
  const address = String(value || "").trim().toLowerCase();
  if (/^0x[0-9a-f]+$/.test(address))
    return address;
  if (/^[0-9a-f]+$/.test(address))
    return "0x" + address;
  return "";
}

function dataForToplevel(toplevel) {
  const ipc = toplevel?.lastIpcObject || {};
  const workspace = toplevel?.workspace;
  const monitor = toplevel?.monitor;
  const monitorId = Number(monitor?.id);
  return Object.assign({}, ipc, {
    address: normalizedAddress(toplevel?.address || ipc.address),
    at: ipc.at || [0, 0],
    size: ipc.size || [480, 300],
    workspace: {
      id: Number(workspace?.id || ipc.workspace?.id || 0),
      name: String(workspace?.name || ipc.workspace?.name || "")
    },
    monitor: Number.isFinite(monitorId) && monitorId >= 0 ? monitorId : ipc.monitor,
    class: String(toplevel?.wayland?.appId || ipc.class || ""),
    initialClass: String(ipc.initialClass || ""),
    title: String(toplevel?.title || ipc.title || ""),
    initialTitle: String(ipc.initialTitle || ""),
    hidden: Boolean(ipc.hidden),
    floating: Boolean(ipc.floating)
  });
}
