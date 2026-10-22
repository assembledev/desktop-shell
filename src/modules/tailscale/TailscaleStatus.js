.pragma library

function route(connection, relay) {
  switch (connection) {
    case "direct": return "Direct";
    case "relay": return "Relay" + (relay ? " · " + relay.toUpperCase() : "");
    case "peer-relay": return "Peer relay";
    case "offline": return "Offline";
    case "idle": return "Idle";
    default: return "Unknown";
  }
}
function lastSeen(value, now) {
  const timestamp = Date.parse(value);
  if (!Number.isFinite(timestamp) || timestamp <= 0)
    return "Offline";
  const minutes = Math.max(0, Math.floor((now - timestamp) / 60000));
  if (minutes < 1) return "Last seen just now";
  if (minutes < 60) return "Last seen " + minutes + " min ago";
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return "Last seen " + hours + " h ago";
  return "Last seen " + Math.floor(hours / 24) + " d ago";
}
function osName(value) {
  return ({linux:"Linux",android:"Android",windows:"Windows",iOS:"iOS",macOS:"macOS",freebsd:"FreeBSD"})[value] || value || "Device";
}
function icon(os) { return os === "android" || os === "iOS" ? "phone" : "display"; }
function bytes(value) {
  if (!Number.isFinite(value)) return "—";
  const units = ["B", "KiB", "MiB", "GiB"];
  let i = 0;
  while (value >= 1024 && i < units.length - 1) { value /= 1024; i++; }
  return (i === 0 ? value.toFixed(0) : value.toFixed(1)) + " " + units[i];
}
function localPath(value) {
  const url = String(value);
  if (!url.startsWith("file:///")) return "";
  try { return decodeURIComponent(url.substring(7)); } catch (error) { return ""; }
}
function probeMatches(probe, id, now) {
  return probe && probe.peerId === id && now - probe.observedAt < 7000;
}

// WaitingFiles contains completed inbox entries. Failed reads must not replace
// the baseline, or a reconnect would announce every old file again.
function waitingFiles(value) {
  if (value === null) return [];
  if (!Array.isArray(value) || value.some(file => !file || typeof file.Name !== "string" || file.Name.length === 0 || !Number.isFinite(file.Size) || file.Size < 0)) return null;
  return value.map(file => ({name:file.Name,size:file.Size}));
}
function inboxUpdate(known, files, available) {
  if (!available) return {known:known,added:[]};
  const keys = files.map(file => JSON.stringify([file.name, file.size]));
  const previous = new Set(known || []);
  return {known:keys,added:known === null ? [] : files.filter((file, index) => !previous.has(keys[index]))};
}
function receivedNotification(files, icon) {
  const escape = value => String(value).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  const shown = files.length > 3 ? 2 : 3;
  let body = files.slice(0, shown).map(file => escape(file.name)).join("<br/>");
  if (files.length > shown) body += "<br/>+" + (files.length - shown) + " more";
  return ["notify-send", "--app-name=Tailscale", "--icon", icon || "folder-download", "--",
    files.length === 1 ? "File received" : files.length + " files received", body];
}
