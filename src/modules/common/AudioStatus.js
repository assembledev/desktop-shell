.pragma library

// PipeWire owns mute state; volume zero does not imply muted.
function icon(audio, input) {
  if (input)
    return audio?.muted ? "mic-off" : "mic";
  return audio?.muted ? "mute" : "speaker";
}

function accent(audio, colors) {
  return audio?.muted ? colors.danger : colors.info;
}
