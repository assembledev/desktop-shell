pragma ComponentBehavior: Bound

import QtQuick
import QtQml.Models
import Quickshell
import Quickshell.Services.Mpris
import "MediaState.js" as MediaState

Scope {
  id: root

  property MprisPlayer activePlayer: null
  property var lastTrackByPlayer: ({})
  property var lastMetadataByPlayer: ({})
  property var lastPlaybackStateByPlayer: ({})
  property var stableTrackByPlayer: ({})
  property string lastActiveSourceId: ""
  property string lastActiveFingerprint: ""
  property string pendingResumeSourceId: ""
  property string pendingResumeFingerprint: ""

  signal trackChanged(var track)
  signal trackResumed(var track)
  signal trackUpdated(var track)

  function sourceId(player) {
    return String(player?.dbusName || player?.identity || "media");
  }

  function playerFingerprint(player) {
    if (!player || String(player.trackTitle || "").trim().length === 0)
      return "";
    return MediaState.trackFingerprint(player.trackTitle, player.trackArtist);
  }

  function sameLogicalTrack(first, second) {
    const fingerprint = playerFingerprint(first);
    return fingerprint.length > 0 && fingerprint === playerFingerprint(second);
  }

  function playerQuality(player) {
    if (!player)
      return -1;

    let score = 0;
    if (String(player.trackTitle || "").trim().length > 0)
      score += 8;
    if (String(player.trackArtist || "").trim().length > 0)
      score += 4;
    if (String(player.trackAlbum || "").trim().length > 0)
      score += 2;
    if (String(player.trackArtUrl || "").trim().length > 0)
      score += 2;
    if (player.lengthSupported && MediaState.finitePositive(player.length) > 0)
      score += 4;
    return score;
  }

  function bestPlayer(candidates, current) {
    let best = candidates.indexOf(current) >= 0 ? current : null;
    let bestQuality = playerQuality(best);
    for (const candidate of candidates) {
      const quality = playerQuality(candidate);
      if (!best || quality > bestQuality) {
        best = candidate;
        bestQuality = quality;
      }
    }
    return best;
  }

  function selectActivePlayer(preferred) {
    const players = Mpris.players.values;
    const playing = players.filter(function(player) {
      return player.isPlaying;
    });

    if (preferred?.isPlaying) {
      const fingerprint = playerFingerprint(preferred);
      const equivalents = fingerprint.length > 0
        ? playing.filter(function(player) {
            return root.playerFingerprint(player) === fingerprint;
          })
        : [preferred];
      activePlayer = bestPlayer(equivalents, activePlayer);
      return;
    }

    if (activePlayer?.isPlaying && playing.indexOf(activePlayer) >= 0) {
      const fingerprint = playerFingerprint(activePlayer);
      const equivalents = fingerprint.length > 0
        ? playing.filter(function(player) {
            return root.playerFingerprint(player) === fingerprint;
          })
        : [activePlayer];
      activePlayer = bestPlayer(equivalents, activePlayer);
      return;
    }

    activePlayer = bestPlayer(playing, null);
    if (!activePlayer && players.length > 0)
      activePlayer = players[0];
  }

  function capturePlayerState(player) {
    if (!player)
      return null;

    const id = sourceId(player);
    const track = MediaState.mergeTrack(stableTrackByPlayer[id], {
      sourceId: id,
      trackKey: id + "\u001f" + String(player.uniqueId ?? 0),
      title: player.trackTitle,
      artist: player.trackArtist,
      album: player.trackAlbum,
      artwork: player.trackArtUrl,
      lengthSupported: player.lengthSupported,
      length: player.length,
      playerName: player.identity || player.desktopEntry
    });
    const nextStable = Object.assign({}, stableTrackByPlayer);
    nextStable[id] = track;
    stableTrackByPlayer = nextStable;
    return track;
  }

  function rememberTrack(track) {
    const nextTracks = Object.assign({}, lastTrackByPlayer);
    const nextMetadata = Object.assign({}, lastMetadataByPlayer);
    nextTracks[track.sourceId] = track.trackKey;
    nextMetadata[track.sourceId] = track.metadataKey;
    lastTrackByPlayer = nextTracks;
    lastMetadataByPlayer = nextMetadata;
  }

  function baselinePlayer(player) {
    const track = capturePlayerState(player);
    if (!track || track.title.length === 0 || lastTrackByPlayer[track.sourceId] !== undefined)
      return;
    rememberTrack(track);
  }

  function rememberPlaybackState(player) {
    const nextStates = Object.assign({}, lastPlaybackStateByPlayer);
    nextStates[sourceId(player)] = player.playbackState;
    lastPlaybackStateByPlayer = nextStates;
  }

  function queueResume(player) {
    pendingResumeSourceId = sourceId(player);
    pendingResumeFingerprint = playerFingerprint(player);
    queueTrackUpdate();
  }

  function clearPendingResume(id) {
    if (pendingResumeSourceId !== id)
      return;
    pendingResumeSourceId = "";
    pendingResumeFingerprint = "";
  }

  function forgetSource(id) {
    const nextTracks = Object.assign({}, lastTrackByPlayer);
    const nextMetadata = Object.assign({}, lastMetadataByPlayer);
    const nextPlaybackStates = Object.assign({}, lastPlaybackStateByPlayer);
    const nextStable = Object.assign({}, stableTrackByPlayer);
    delete nextTracks[id];
    delete nextMetadata[id];
    delete nextPlaybackStates[id];
    delete nextStable[id];
    lastTrackByPlayer = nextTracks;
    lastMetadataByPlayer = nextMetadata;
    lastPlaybackStateByPlayer = nextPlaybackStates;
    stableTrackByPlayer = nextStable;
    clearPendingResume(id);
  }

  function maybeEmitTrack() {
    const player = activePlayer;
    if (!player?.isPlaying)
      return;

    const track = capturePlayerState(player);
    if (!track || track.title.length === 0)
      return;

    const previousTrack = lastTrackByPlayer[track.sourceId];
    const previousMetadata = lastMetadataByPlayer[track.sourceId];
    const resumed = pendingResumeSourceId === track.sourceId
      || (pendingResumeFingerprint.length > 0
          && pendingResumeFingerprint === track.fingerprint);
    pendingResumeSourceId = "";
    pendingResumeFingerprint = "";
    rememberTrack(track);

    if (previousTrack === undefined) {
      lastActiveSourceId = track.sourceId;
      lastActiveFingerprint = track.fingerprint;
      return;
    }

    if (previousTrack !== track.trackKey) {
      const equivalentProviderUpdate = lastActiveSourceId.length > 0
        && lastActiveSourceId !== track.sourceId
        && lastActiveFingerprint.length > 0
        && lastActiveFingerprint === track.fingerprint;
      if (equivalentProviderUpdate)
        trackUpdated(track);
      else
        trackChanged(track);
    } else if (resumed) {
      trackResumed(track);
    } else if (previousMetadata !== track.metadataKey) {
      trackUpdated(track);
    }

    lastActiveSourceId = track.sourceId;
    lastActiveFingerprint = track.fingerprint;
  }

  function queueTrackUpdate() {
    trackDebounce.restart();
  }

  function captureActivePlayer() {
    capturePlayerState(activePlayer);
    queueTrackUpdate();
  }

  onActivePlayerChanged: captureActivePlayer()

  Timer {
    id: trackDebounce
    interval: 180
    onTriggered: root.maybeEmitTrack()
  }

  Instantiator {
    model: Mpris.players

    Connections {
      required property MprisPlayer modelData
      readonly property string trackedSourceId: root.sourceId(modelData)
      target: modelData

      function handleMetadataChange(preferPlayer) {
        root.capturePlayerState(modelData);
        if (modelData.isPlaying
            && (preferPlayer || root.sameLogicalTrack(modelData, root.activePlayer)))
          root.selectActivePlayer(modelData);
        if (root.activePlayer === modelData)
          root.queueTrackUpdate();
      }

      Component.onCompleted: {
        root.rememberPlaybackState(modelData);
        root.baselinePlayer(modelData);
        if (modelData.isPlaying)
          root.selectActivePlayer(modelData);
        if (root.activePlayer === modelData)
          root.queueTrackUpdate();
      }

      Component.onDestruction: {
        root.forgetSource(trackedSourceId);
        if (root.activePlayer === modelData) {
          root.activePlayer = null;
          Qt.callLater(function() {
            root.selectActivePlayer(null);
            root.queueTrackUpdate();
          });
        }
      }

      function onPlaybackStateChanged() {
        const previousPlaybackState = root.lastPlaybackStateByPlayer[trackedSourceId];
        const resumedFromPause = previousPlaybackState === MprisPlaybackState.Paused
          && modelData.playbackState === MprisPlaybackState.Playing;
        root.rememberPlaybackState(modelData);
        root.capturePlayerState(modelData);
        if (modelData.isPlaying)
          root.selectActivePlayer(modelData);
        else {
          root.clearPendingResume(trackedSourceId);
          if (root.activePlayer === modelData)
            root.selectActivePlayer(null);
        }
        if (resumedFromPause)
          root.queueResume(modelData);
        else if (root.activePlayer === modelData)
          root.queueTrackUpdate();
      }

      function onPostTrackChanged() {
        handleMetadataChange(true);
      }

      function onTrackTitleChanged() {
        handleMetadataChange(false);
      }

      function onTrackArtistChanged() {
        handleMetadataChange(false);
      }

      function onTrackAlbumChanged() {
        handleMetadataChange(false);
      }

      function onTrackArtUrlChanged() {
        handleMetadataChange(false);
      }

      function onLengthChanged() {
        handleMetadataChange(false);
      }

      function onLengthSupportedChanged() {
        handleMetadataChange(false);
      }
    }
  }

  Component.onCompleted: Qt.callLater(function() {
    root.selectActivePlayer(null);
    root.queueTrackUpdate();
  })
}
