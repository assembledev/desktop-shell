import QtQuick
import QtTest
import "../../src/modules/control_center/AudioCommands.js" as Audio
import "../../src/modules/now_playing/MediaCommands.js" as Media

TestCase {
  name: "DesktopCommands"

  function node(id, name, sink, stream) {
    return { id: id, name: name, description: name, isSink: sink, isStream: stream,
             ready: true, audio: { volume: 0.5, muted: true } };
  }

  function service() {
    const speaker = node(1, "speaker", true, false);
    const mic = node(2, "mic", false, false);
    const app = node(3, "app", false, true);
    return { ready: true, nodes: { values: [speaker, mic, app] },
             defaultAudioSink: speaker, defaultAudioSource: mic };
  }

  function test_audio_snapshot_and_target_identity() {
    const api = service();
    const state = Audio.snapshot(api);
    verify(state.ready);
    compare(state.outputs.length, 1);
    compare(state.inputs.length, 1);
    compare(state.streams.length, 1);
    compare(state.defaultOutput.id, "1");
    compare(Audio.select(api, "input"), api.defaultAudioSource);
    compare(Audio.select(api, "speaker"), api.defaultAudioSink);
    compare(Audio.select(api, "3"), api.nodes.values[2]);
    compare(Audio.select(api, "absent"), null);
    api.nodes.values.push(node(4, "speaker", true, false));
    compare(Audio.select(api, "speaker"), null);
  }

  function test_audio_volume_is_bounded_and_preserves_mute() {
    const api = service();
    verify(Audio.command(api, "volume", "output", "35").accepted);
    compare(api.defaultAudioSink.audio.volume, 0.35);
    verify(api.defaultAudioSink.audio.muted);
    for (const value of ["", "-1", "151", "NaN", "Infinity"])
      compare(Audio.command(api, "volume", "output", value).error.code, "invalid-argument");
    compare(api.defaultAudioSink.audio.volume, 0.35);
    Audio.setVolume(api.defaultAudioSink, 0.75, true);
    verify(!api.defaultAudioSink.audio.muted);
  }

  function test_audio_mute_default_and_disappearing_targets() {
    const api = service();
    verify(Audio.command(api, "mute", "input", "off").accepted);
    verify(!api.defaultAudioSource.audio.muted);
    verify(Audio.command(api, "mute", "input", "toggle").muted);
    compare(Audio.command(api, "mute", "input", "garbage").error.code, "invalid-argument");
    compare(Audio.command(api, "default", "3", "input").error.code, "invalid-argument");
    compare(Audio.command(api, "default", "mic", "output").error.code, "invalid-argument");
    verify(Audio.command(api, "default", "mic", "input").accepted);
    compare(api.preferredDefaultAudioSource, api.defaultAudioSource);
    api.defaultAudioSource.ready = false;
    verify(!Audio.snapshot(api).ready);
    compare(Audio.command(api, "volume", "input", "50").error.code, "not-ready");
    api.nodes.values = [];
    compare(Audio.command(api, "mute", "3", "off").error.code, "not-found");
  }

  function test_media_capabilities_and_explicit_player() {
    let calls = [];
    const player = { dbusName: "org.mpris.MediaPlayer2.test", identity: "Test", canControl: true,
                     canPlay: true, canPause: true, canTogglePlaying: true, canGoNext: false,
                     canGoPrevious: false, play: function() { calls.push("play"); },
                     togglePlaying: function() { calls.push("toggle"); } };
    compare(Media.snapshot([player], player).active, player.dbusName);
    compare(Media.snapshot([], null).players.length, 0);
    verify(Media.command([player], null, "play", player.dbusName).accepted);
    verify(Media.command([player], player, "toggle", "active").accepted);
    compare(calls.join(","), "play,toggle");
    compare(Media.command([player], player, "next", "active").error.code, "unsupported");
    compare(Media.command([player], player, "quit", "active").error.code, "unsupported");
    compare(Media.command([], null, "play", "active").error.code, "not-found");
    player.canControl = false;
    compare(Media.command([player], player, "play", "active").error.code, "unsupported");
    compare(calls.length, 2);
  }
}
