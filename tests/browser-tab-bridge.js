const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const vm = require("node:vm");

const sourceRoot = process.argv[2];
assert.ok(sourceRoot, "source root is required");
const source = fs.readFileSync(path.join(sourceRoot, "browser-extension/extension/background.js"), "utf8");

function event() {
  return {
    listeners: [],
    addListener(callback) { this.listeners.push(callback); },
    emit(...args) { this.listeners.forEach(callback => callback(...args)); }
  };
}

function harness() {
  const timers = new Map();
  const ports = [];
  let nextTimer = 1;
  const browser = {
    runtime: {
      onStartup: event(),
      connectNative() {
        const port = { onMessage: event(), onDisconnect: event(), postMessage() {} };
        ports.push(port);
        return port;
      }
    },
    tabs: Object.fromEntries([
      "onActivated", "onAttached", "onCreated", "onDetached", "onMoved", "onRemoved", "onUpdated"
    ].map(name => [name, event()])),
    windows: Object.fromEntries([
      "onCreated", "onFocusChanged", "onRemoved"
    ].map(name => [name, event()]))
  };
  vm.runInNewContext(source, {
    browser, URL, console: { error() {} },
    setTimeout(callback, delay) {
      const id = nextTimer++;
      timers.set(id, { callback, delay });
      return id;
    },
    clearTimeout(id) { timers.delete(id); }
  });
  return {
    browser, ports,
    reconnect(expectedDelay) {
      const [id, timer] = [...timers].find(([, value]) => value.delay >= 1000);
      assert.equal(timer.delay, expectedDelay);
      timers.delete(id);
      timer.callback();
    }
  };
}

const failed = harness();
for (const delay of [1000, 2000, 4000, 8000, 16000, 30000, 30000]) {
  failed.ports.at(-1).onDisconnect.emit();
  const attempts = failed.ports.length;
  failed.browser.tabs.onUpdated.emit();
  failed.browser.runtime.onStartup.emit();
  assert.equal(failed.ports.length, attempts, "events must respect reconnect backoff");
  failed.reconnect(delay);
  assert.equal(failed.ports.length, attempts + 1);
}

// Only a response from the current native host resets the failure delay.
failed.ports.at(-1).onMessage.emit({ type: "ready" });
failed.ports.at(-1).onDisconnect.emit();
failed.reconnect(1000);
failed.ports.at(-2).onMessage.emit({ type: "ready" });
failed.ports.at(-2).onDisconnect.emit();
failed.ports.at(-1).onDisconnect.emit();
failed.reconnect(2000);

const runtimeRoot = fs.mkdtempSync(path.join(os.tmpdir(), "browser-bridge-test-"));
try {
  const host = spawnSync("python3", [path.join(sourceRoot, "browser-extension/native-host.py")], {
    input: Buffer.alloc(0),
    env: { ...process.env, XDG_RUNTIME_DIR: runtimeRoot },
    timeout: 5000
  });
  assert.equal(host.status, 0, host.stderr.toString());
  assert.ok(host.stdout.length >= 4, "native host must acknowledge readiness");
  const length = os.endianness() === "LE" ? host.stdout.readUInt32LE(0) : host.stdout.readUInt32BE(0);
  assert.deepEqual(JSON.parse(host.stdout.subarray(4, 4 + length).toString()), { type: "ready" });
  assert.equal(fs.existsSync(path.join(runtimeRoot, "desktop-shell/browser-tabs.sock")), false);
} finally {
  fs.rmSync(runtimeRoot, { recursive: true, force: true });
}
