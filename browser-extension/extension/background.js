const NATIVE_HOST = "io.desktop_shell.browser_tabs";
const SNAPSHOT_DEBOUNCE_MS = 60;
const RECONNECT_MAX_MS = 30000;

let nativePort = null;
let publishTimer = null;
let reconnectTimer = null;
let reconnectDelayMs = 1000;

function tabHost(rawUrl) {
  try {
    const url = new URL(rawUrl || "");
    if (url.host)
      return url.host;
    return url.protocol.replace(/:$/, "");
  } catch (_error) {
    return "";
  }
}

async function collectGroups() {
  if (!browser.tabGroups)
    return new Map();

  const groups = await browser.tabGroups.query({});
  return new Map(groups.map(group => [
    group.id,
    {
      title: group.title || "",
      color: group.color || ""
    }
  ]));
}

async function collectSnapshot() {
  const [tabs, windows, groups] = await Promise.all([
    browser.tabs.query({}),
    browser.windows.getAll({ windowTypes: ["normal"] }),
    collectGroups()
  ]);
  const focusedWindowIds = new Set(
    windows.filter(window => window.focused).map(window => window.id)
  );

  return tabs
    .filter(tab => !tab.incognito && Number.isInteger(tab.id) && Number.isInteger(tab.windowId))
    .map(tab => {
      const group = groups.get(tab.groupId) || {};
      return {
        tabId: tab.id,
        windowId: tab.windowId,
        title: tab.title || "Untitled tab",
        host: tabHost(tab.url),
        group: group.title || "",
        groupColor: group.color || "",
        active: Boolean(tab.active),
        current: Boolean(tab.active && focusedWindowIds.has(tab.windowId)),
        pinned: Boolean(tab.pinned),
        audible: Boolean(tab.audible),
        muted: Boolean(tab.mutedInfo?.muted),
        lastAccessed: Number(tab.lastAccessed || 0)
      };
    });
}

async function publishSnapshot() {
  publishTimer = null;
  if (!nativePort)
    return;

  try {
    nativePort.postMessage({
      type: "snapshot",
      generatedAt: Date.now(),
      tabs: await collectSnapshot()
    });
  } catch (error) {
    console.error("desktop-shell-tabs: failed to publish tab snapshot", error);
  }
}

function schedulePublish() {
  if (!nativePort)
    connectNativeHost();
  if (publishTimer !== null)
    clearTimeout(publishTimer);
  publishTimer = setTimeout(publishSnapshot, SNAPSHOT_DEBOUNCE_MS);
}

async function activateTab(message) {
  try {
    await browser.tabs.update(message.tabId, { active: true });
    await browser.windows.update(message.windowId, { focused: true });
    nativePort?.postMessage({
      type: "activateResult",
      requestId: message.requestId,
      ok: true
    });
    schedulePublish();
  } catch (error) {
    nativePort?.postMessage({
      type: "activateResult",
      requestId: message.requestId,
      ok: false,
      error: String(error?.message || error)
    });
  }
}

function scheduleReconnect() {
  if (reconnectTimer !== null)
    return;

  reconnectTimer = setTimeout(() => {
    reconnectTimer = null;
    connectNativeHost();
  }, reconnectDelayMs);
  reconnectDelayMs = Math.min(RECONNECT_MAX_MS, reconnectDelayMs * 2);
}

function connectNativeHost() {
  if (nativePort)
    return;

  try {
    const port = browser.runtime.connectNative(NATIVE_HOST);
    nativePort = port;
    reconnectDelayMs = 1000;

    port.onMessage.addListener(message => {
      if (message?.type === "activate")
        activateTab(message);
    });
    port.onDisconnect.addListener(() => {
      if (nativePort === port)
        nativePort = null;
      scheduleReconnect();
    });
    schedulePublish();
  } catch (error) {
    console.error("desktop-shell-tabs: failed to connect native host", error);
    scheduleReconnect();
  }
}

[
  browser.tabs.onActivated,
  browser.tabs.onAttached,
  browser.tabs.onCreated,
  browser.tabs.onDetached,
  browser.tabs.onMoved,
  browser.tabs.onRemoved,
  browser.tabs.onUpdated,
  browser.windows.onCreated,
  browser.windows.onFocusChanged,
  browser.windows.onRemoved
].forEach(event => event.addListener(schedulePublish));

if (browser.tabGroups) {
  [
    browser.tabGroups.onCreated,
    browser.tabGroups.onMoved,
    browser.tabGroups.onRemoved,
    browser.tabGroups.onUpdated
  ].forEach(event => event.addListener(schedulePublish));
}

browser.runtime.onStartup.addListener(connectNativeHost);
connectNativeHost();
