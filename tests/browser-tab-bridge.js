const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawn, spawnSync } = require("node:child_process");
const { once } = require("node:events");
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
        const port = {
          onMessage: event(), onDisconnect: event(), messages: [],
          postMessage(message) { this.messages.push(message); }
        };
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
    publish() {
      const [id, timer] = [...timers].find(([, value]) => value.delay === 60);
      timers.delete(id);
      return timer.callback();
    },
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

async function checkHostTermination(signal, partialMessage) {
  const runtimeRoot = fs.mkdtempSync(path.join(os.tmpdir(), "browser-bridge-signal-"));
  const host = spawn("python3", [path.join(sourceRoot, "browser-extension/native-host.py")], {
    env: { ...process.env, XDG_RUNTIME_DIR: runtimeRoot }
  });
  const exited = once(host, "exit");
  const timeout = setTimeout(() => host.kill("SIGKILL"), 3000);
  let stderr = "";
  host.stderr.on("data", data => { stderr += data; });
  try {
    await Promise.race([
      once(host.stdout, "data"),
      exited.then(() => { throw new Error(`host exited before readiness: ${stderr}`); })
    ]);
    assert.equal(fs.existsSync(path.join(runtimeRoot, "desktop-shell/browser-tabs.json")), true);
    if (partialMessage.length)
      host.stdin.write(partialMessage);
    host.kill(signal);
    const [code, exitSignal] = await exited;
    assert.equal(exitSignal, null, `host did not handle ${signal}: ${stderr}`);
    assert.equal(code, 0, stderr);
    assert.equal(fs.existsSync(path.join(runtimeRoot, "desktop-shell/browser-tabs.sock")), false);
    assert.equal(fs.existsSync(path.join(runtimeRoot, "desktop-shell/browser-tabs.json")), false);
  } finally {
    clearTimeout(timeout);
    host.stdin.destroy();
    host.kill("SIGKILL");
    await exited;
    fs.rmSync(runtimeRoot, { recursive: true, force: true });
  }
}

async function checkSignalCleanup() {
  const header = Buffer.alloc(4);
  if (os.endianness() === "LE")
    header.writeUInt32LE(32);
  else
    header.writeUInt32BE(32);
  for (const signal of ["SIGTERM", "SIGINT"]) {
    await checkHostTermination(signal, Buffer.alloc(0));
    await checkHostTermination(signal, header.subarray(0, 2));
    await checkHostTermination(signal, Buffer.concat([header, Buffer.from("{")]));
  }
}

async function checkSnapshotOrdering() {
  const h = harness();
  const pending = [];
  h.browser.tabs.query = () => new Promise(resolve => pending.push(resolve));
  h.browser.windows.getAll = async () => [];
  const tab = title => [{ id: 1, windowId: 1, title }];

  const first = h.publish();
  h.browser.tabs.onUpdated.emit();
  const second = h.publish();
  pending[1](tab("newer"));
  await second;
  pending[0](tab("older"));
  await first;
  assert.deepEqual(h.ports[0].messages.map(message => message.tabs[0].title), ["newer"],
    "late collections must not overwrite a newer snapshot");

  h.browser.tabs.onUpdated.emit();
  const disconnected = h.publish();
  h.ports[0].onDisconnect.emit();
  h.reconnect(1000);
  pending[2](tab("old connection"));
  await disconnected;
  assert.equal(h.ports[1].messages.length, 0,
    "a collection from the old connection must not publish to the new host");
  const reconnected = h.publish();
  pending[3](tab("new connection"));
  await reconnected;
  assert.equal(h.ports[1].messages[0].tabs[0].title, "new connection");
}

async function main() {
  await checkSnapshotOrdering();
  await checkSignalCleanup();
}

main().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
