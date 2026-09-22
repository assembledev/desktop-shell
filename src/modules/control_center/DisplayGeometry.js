.pragma library

function position(value) {
  const match = /^(-?\d+)x(-?\d+)$/.exec(String(value || ""));
  return match ? { x: Number(match[1]), y: Number(match[2]) } : { x: 0, y: 0 };
}

function rect(output, draft) {
  const values = (draft || {})[output.name] || {};
  const mode = String(values.mode === undefined ? output.mode : values.mode);
  const match = /^(\d+)x(\d+)(?:@|$)/.exec(mode);
  let width = match ? Number(match[1]) : Math.max(1, Number(output.width || 1920));
  let height = match ? Number(match[2]) : Math.max(1, Number(output.height || 1080));
  if (Number(output.transform || 0) % 2 === 1) {
    const swap = width;
    width = height;
    height = swap;
  }
  const scale = Math.max(0.5, Number(values.scale === undefined ? output.scale || 1 : values.scale));
  const at = position(values.position === undefined ? output.position : values.position);
  return { x: at.x, y: at.y, width: width / scale, height: height / scale };
}

function bounds(outputs, draft) {
  let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
  for (const output of outputs) {
    const box = rect(output, draft);
    minX = Math.min(minX, box.x);
    minY = Math.min(minY, box.y);
    maxX = Math.max(maxX, box.x + box.width);
    maxY = Math.max(maxY, box.y + box.height);
  }
  return outputs.length ? { minX, minY, maxX, maxY } : { minX: 0, minY: 0, maxX: 1, maxY: 1 };
}

function viewport(outputs, draft, width, height, padding) {
  const box = bounds(outputs, draft);
  const w = Math.max(1, box.maxX - box.minX), h = Math.max(1, box.maxY - box.minY);
  const scale = Math.max(0.001, Math.min((width - padding * 2) / w, (height - padding * 2) / h));
  return { scale, minX: box.minX, minY: box.minY, x: (width - w * scale) / 2, y: (height - h * scale) / 2 };
}

function adjacent(box, other, side, alignment) {
  const fraction = alignment === "start" ? 0 : alignment === "end" ? 1 : 0.5;
  if (side === "left" || side === "right")
    return { x: side === "left" ? other.x - box.width : other.x + other.width,
      y: other.y + (other.height - box.height) * fraction };
  return { x: other.x + (other.width - box.width) * fraction,
    y: side === "top" ? other.y - box.height : other.y + other.height };
}

// Dragging chooses one of three exact alignments on each neighboring edge.
// Keep the last placement if a crowded layout has no unoccupied candidate.
function snap(outputs, draft, name, x, y) {
  const output = outputs.find(candidate => candidate.name === name);
  if (!output)
    return { x, y };
  const box = rect(output, draft);
  const neighbors = outputs.filter(candidate => candidate.name !== name).map(candidate => rect(candidate, draft));
  let result = { x: box.x, y: box.y }, bestDistance = Infinity;
  for (const target of neighbors) {
    for (const side of ["left", "right", "top", "bottom"]) {
      for (const alignment of ["start", "center", "end"]) {
        const position = adjacent(box, target, side, alignment);
        const candidate = { x: Math.round(position.x), y: Math.round(position.y) };
        const overlaps = neighbors.some(other => candidate.x < other.x + other.width - 0.001
          && candidate.x + box.width > other.x + 0.001
          && candidate.y < other.y + other.height - 0.001
          && candidate.y + box.height > other.y + 0.001);
        if (overlaps)
          continue;
        const distance = Math.pow(candidate.x - x, 2) + Math.pow(candidate.y - y, 2);
        if (distance < bestDistance) {
          bestDistance = distance;
          result = candidate;
        }
      }
    }
  }
  return result;
}
