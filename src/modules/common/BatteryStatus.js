.pragma library

function capacity(data) {
  const value = Number(data.capacity);
  return Number.isFinite(value) ? Math.max(0, Math.min(100, Math.round(value))) : 0;
}

function externallyPowered(data) {
  return data.status === "Charging" || data.status === "Full";
}

function icon(data) {
  if (data.status === "Charging")
    return "󰂄";
  if (data.status === "Full")
    return "󰁹";
  return ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"][Math.min(9, Math.floor(capacity(data) / 10))];
}

function severity(data) {
  if (externallyPowered(data))
    return "normal";
  return capacity(data) <= 15 ? "critical" : capacity(data) <= 30 ? "low" : "normal";
}
