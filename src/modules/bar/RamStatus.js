.pragma library

function unavailable() {
  return { available: false, ram: 0, ramText: "--" };
}

function parse(text) {
  const values = {};
  for (const line of String(text).split("\n")) {
    const match = /^(MemTotal|MemAvailable):\s+(\d+)\s+kB\s*$/.exec(line);
    if (match) values[match[1]] = Number(match[2]);
  }
  const total = values.MemTotal;
  const available = values.MemAvailable;
  if (!Number.isFinite(total) || total <= 0 || !Number.isFinite(available)
      || available < 0 || available > total)
    return unavailable();
  const used = total - available;
  return { available: true, ram: used / total,
    ramText: (used / 1048576).toFixed(1) + "/" + (total / 1048576).toFixed(0) + "G" };
}
