.pragma library

function signalLevel(signal) {
  if (signal === null || !Number.isFinite(Number(signal)))
    return "wifi";
  const percent = Math.max(0, Math.min(100, Number(signal)));
  return percent >= 75 ? "wifi" : percent >= 50 ? "wifi-medium" : percent >= 25 ? "wifi-weak" : "wifi-minimal";
}

function traffic(previous, next, now) {
  const baseline = { interface: next.interface, rx: next.rxBytes, tx: next.txBytes, time: now };
  const elapsed = previous ? (now - previous.time) / 1000 : 0;
  if (!previous || previous.interface !== next.interface || elapsed <= 0 || elapsed > 10
      || next.rxBytes === null || next.txBytes === null || previous.rx === null || previous.tx === null
      || next.rxBytes < previous.rx || next.txBytes < previous.tx)
    return { baseline: baseline, receive: null, transmit: null };
  return { baseline: baseline, receive: (next.rxBytes - previous.rx) / elapsed, transmit: (next.txBytes - previous.tx) / elapsed };
}

function rate(bytes) {
  if (bytes === null || !Number.isFinite(Number(bytes)))
    return "—";
  const value = Math.max(0, Number(bytes));
  if (value >= 1000000)
    return (value / 1000000).toFixed(1) + " MB/s";
  if (value >= 1000)
    return Math.round(value / 1000) + " KB/s";
  return Math.round(value) + " B/s";
}

function linkRate(mbps) {
  if (mbps === null || !Number.isFinite(Number(mbps)) || Number(mbps) <= 0)
    return "—";
  return Number(mbps) >= 1000 ? Number((Number(mbps) / 1000).toFixed(2)) + " Gb/s" : Math.round(Number(mbps)) + " Mb/s";
}

function band(frequency) {
  const mhz = Number(frequency);
  return mhz >= 5925 ? "6 GHz" : mhz >= 4900 ? "5 GHz" : mhz >= 2400 ? "2.4 GHz" : "";
}
