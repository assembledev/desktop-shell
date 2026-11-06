.pragma library

function capacity(data) {
  const value = Number(data.capacity);
  return Number.isFinite(value) ? Math.max(0, Math.min(100, Math.round(value))) : 0;
}

function externallyPowered(data) {
  return typeof data.onBattery === "boolean" ? !data.onBattery
    : data.status === "Charging" || data.status === "Full";
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
  const low = Number(data.lowPercentage ?? 30);
  const critical = Number(data.criticalPercentage ?? 15);
  return capacity(data) <= critical ? "critical" : capacity(data) <= low ? "low" : "normal";
}

function duration(seconds) {
  if (!(seconds > 0))
    return "--";
  const minutes = Math.round(seconds / 60);
  return minutes >= 60 ? Math.floor(minutes / 60) + "h "
    + String(minutes % 60).padStart(2, "0") + "m" : minutes + "m";
}

function analysis(data, drain) {
  const discharging = data.status === "Discharging" && !externallyPowered(data);
  const seconds = discharging ? Math.max(0, Math.round(data.timeToEmpty || 0)) : 0;
  return Object.assign({}, drain, {
    estimateSeconds: seconds,
    estimateText: data.status === "Charging" ? "charging"
      : data.status === "Full" ? "full"
      : externallyPowered(data) ? "plugged in" : duration(seconds),
    currentDraw: discharging && data.changeRate > 0 ? data.changeRate.toFixed(1) + " W" : "--"
  });
}
