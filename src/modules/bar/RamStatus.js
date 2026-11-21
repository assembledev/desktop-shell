.pragma library

function unavailable() {
  return { available: false, ram: 0, ramText: "--", details: null };
}

function formatAmount(kib) {
  if (kib >= 1048576) return (kib / 1048576).toFixed(1) + " GiB";
  if (kib >= 1024 || kib === 0) return Math.round(kib / 1024) + " MiB";
  return kib + " KiB";
}

// ps returns descending RSS, with PID as the tie-breaker.
function topProcesses(text) {
  const processes = [];
  for (const line of String(text).split("\n")) {
    const match = /^\s*(\d+)\s+(\d+)\s+(\S.*)$/.exec(line);
    if (!match) continue;
    const pid = Number(match[1]);
    const rssKiB = Number(match[2]);
    if (pid <= 0 || !Number.isSafeInteger(pid) || rssKiB <= 0 || !Number.isSafeInteger(rssKiB)) continue;
    processes.push({ pid: pid, rssKiB: rssKiB, name: match[3].trim() });
    if (processes.length === 3) break;
  }
  return processes;
}

function parse(text) {
  const values = {};
  for (const line of String(text).split("\n")) {
    const match = /^(MemTotal|MemAvailable|MemFree|SwapTotal|SwapFree):\s+(\d+)\s+kB\s*$/.exec(line);
    if (match) values[match[1]] = Number(match[2]);
  }
  const total = values.MemTotal;
  const available = values.MemAvailable;
  if (!Number.isFinite(total) || total <= 0 || !Number.isFinite(available)
      || available < 0 || available > total)
    return unavailable();
  const used = total - available;
  const free = values.MemFree;
  // MemAvailable already discounts kernel reserves and the cache Linux expects to keep.
  const reclaimable = Number.isFinite(free) && free < available ? available - free : 0;
  const swapTotal = values.SwapTotal;
  const swapFree = values.SwapFree;
  const swap = Number.isFinite(swapTotal) && swapTotal > 0 && Number.isFinite(swapFree) && swapFree <= swapTotal
    ? { totalKiB: swapTotal, usedKiB: swapTotal - swapFree }
    : null;
  return { available: true, ram: used / total,
    ramText: (used / 1048576).toFixed(1) + "/" + (total / 1048576).toFixed(0) + "G",
    details: { totalKiB: total, usedKiB: used, reclaimableKiB: reclaimable, swap: swap }
  };
}
