.pragma library

function describe(player) {
  return {
    id: String(player.dbusName), name: String(player.identity || player.desktopEntry || ""),
    playing: Boolean(player.isPlaying), title: String(player.trackTitle || ""),
    artist: String(player.trackArtist || ""), album: String(player.trackAlbum || ""),
    position: player.positionSupported ? Number(player.position) : null,
    length: player.lengthSupported ? Number(player.length) : null,
    capabilities: {
      play: Boolean(player.canControl && player.canPlay),
      pause: Boolean(player.canControl && player.canPause),
      toggle: Boolean(player.canControl && player.canTogglePlaying),
      stop: Boolean(player.canControl),
      next: Boolean(player.canControl && player.canGoNext),
      previous: Boolean(player.canControl && player.canGoPrevious)
    }
  };
}

function snapshot(players, active) {
  return { active: active ? String(active.dbusName) : null, players: players.map(describe) };
}

function command(players, active, action, selector) {
  const player = selector === "active" ? active : players.find(function(candidate) {
    return candidate.dbusName === selector;
  });
  if (!player)
    return { error: { code: "not-found", message: "Media player is not available" } };
  const state = describe(player);
  if (!Object.prototype.hasOwnProperty.call(state.capabilities, action) || !state.capabilities[action])
    return { error: { code: "unsupported", message: "Player does not support this operation" } };
  if (action === "toggle")
    player.togglePlaying();
  else
    player[action]();
  return { accepted: true, player: state.id, action: action };
}
