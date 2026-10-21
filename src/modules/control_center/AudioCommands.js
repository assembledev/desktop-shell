.pragma library

function failure(code, message) { return { error: { code: code, message: message } }; }

function nodes(service) {
  return (service.nodes.values || []).filter(function(node) { return node && node.audio; });
}

function describe(node) {
  if (!node)
    return null;
  return {
    id: String(node.id), name: String(node.name || ""),
    description: String(node.description || node.name || ""),
    stream: Boolean(node.isStream), sink: Boolean(node.isSink), ready: Boolean(node.ready),
    volume: node.ready ? Math.round(Number(node.audio.volume) * 1000) / 10 : null,
    muted: node.ready ? Boolean(node.audio.muted) : null
  };
}

function snapshot(service) {
  const all = nodes(service);
  return {
    ready: Boolean(service.ready) && all.every(function(node) { return node.ready; }),
    defaultOutput: describe(service.defaultAudioSink),
    defaultInput: describe(service.defaultAudioSource),
    outputs: all.filter(function(node) { return !node.isStream && node.isSink; }).map(describe),
    inputs: all.filter(function(node) { return !node.isStream && !node.isSink; }).map(describe),
    streams: all.filter(function(node) { return node.isStream; }).map(describe)
  };
}

function select(service, selector) {
  if (selector === "output")
    return service.defaultAudioSink;
  if (selector === "input")
    return service.defaultAudioSource;
  const matches = nodes(service).filter(function(node) {
    return String(node.id) === selector || node.name === selector;
  });
  return matches.length === 1 ? matches[0] : null;
}

function setVolume(node, fraction, unmute) {
  if (!node?.ready || !node.audio || !Number.isFinite(fraction) || fraction < 0 || fraction > 1.5)
    return false;
  node.audio.volume = fraction;
  if (unmute)
    node.audio.muted = false;
  return true;
}

function command(service, action, selector, value) {
  if (!service.ready)
    return failure("not-ready", "PipeWire is not ready");
  const node = select(service, selector);
  if (!node)
    return failure("not-found", "No unique audio node matches the target");
  if (!node.ready)
    return failure("not-ready", "Audio node is not ready");
  if (action === "volume") {
    const percent = Number(value);
    if (String(value).trim().length === 0 || !setVolume(node, percent / 100, false))
      return failure("invalid-argument", "Volume must be between 0 and 150 percent");
    return { accepted: true, target: String(node.id), name: String(node.name), volume: percent };
  }
  if (action === "mute") {
    if (!["on", "off", "toggle"].includes(value))
      return failure("invalid-argument", "Mute must be on, off or toggle");
    const muted = value === "toggle" ? !node.audio.muted : value === "on";
    node.audio.muted = muted;
    return { accepted: true, target: String(node.id), name: String(node.name), muted: muted };
  }
  if (action === "default") {
    if (node.isStream || !["output", "input"].includes(value) || node.isSink !== (value === "output"))
      return failure("invalid-argument", "Default target must be a device of the requested direction");
    if (value === "output")
      service.preferredDefaultAudioSink = node;
    else
      service.preferredDefaultAudioSource = node;
    return { accepted: true, target: String(node.id), name: String(node.name), direction: value };
  }
  return failure("invalid-argument", "Unknown audio operation");
}
