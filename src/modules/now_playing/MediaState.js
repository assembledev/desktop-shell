function finitePositive(value) {
  var number = Number(value || 0);
  return Number.isFinite(number) && number > 0 ? number : 0;
}

function normalized(value) {
  return String(value || "").trim();
}

function trackFingerprint(title, artist) {
  return normalized(title).toLocaleLowerCase()
    + "\u001f"
    + normalized(artist).toLocaleLowerCase();
}

function metadataKey(track) {
  return [track.title, track.artist, track.album, track.artwork, track.length].join("\u001f");
}

function mergeTrack(previous, raw) {
  var stable = previous && previous.trackKey === raw.trackKey ? previous : {};
  var title = normalized(raw.title) || stable.title || "";
  var artist = normalized(raw.artist) || stable.artist || "";
  var album = normalized(raw.album) || stable.album || "";
  var artwork = normalized(raw.artwork) || stable.artwork || "";
  var reportedLength = raw.lengthSupported ? finitePositive(raw.length) : 0;
  var length = reportedLength || finitePositive(stable.length);
  var track = {
    sourceId: raw.sourceId,
    trackKey: raw.trackKey,
    title: title,
    artist: artist,
    album: album,
    artwork: artwork,
    length: length,
    playerName: normalized(raw.playerName) || "Media",
    fingerprint: trackFingerprint(title, artist)
  };
  track.metadataKey = metadataKey(track);
  return track;
}
