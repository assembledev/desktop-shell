import QtQuick
import QtTest
import "../../src/modules/common/AudioStatus.js" as AudioStatus

TestCase {
  id: suite
  name: "AudioStatus"

  readonly property var colors: ({ info: "#67d4e8", danger: "#f283a2" })
  QtObject {
    id: audio
    property bool muted: false
    property real volume: 0.64
  }
  QtObject {
    id: presentation
    property var current: audio
    readonly property string outputIcon: AudioStatus.icon(current)
    readonly property string inputIcon: AudioStatus.icon(current, true)
    readonly property string accent: AudioStatus.accent(current, suite.colors)
  }

  function init() {
    audio.muted = false;
    audio.volume = 0.64;
    presentation.current = audio;
  }

  function test_mute_is_independent_of_volume_data() {
    return [
      { tag: "silent", volume: 0 },
      { tag: "audible", volume: 0.64 },
      { tag: "boosted", volume: 1.5 }
    ];
  }

  function test_mute_is_independent_of_volume(data) {
    audio.volume = data.volume;
    compare(presentation.outputIcon, "speaker");
    compare(presentation.inputIcon, "mic");
    compare(presentation.accent, colors.info);
    audio.muted = true;
    compare(presentation.outputIcon, "mute");
    compare(presentation.inputIcon, "mic-off");
    compare(presentation.accent, colors.danger);
    audio.volume = 0.25;
    compare(presentation.outputIcon, "mute");
    audio.muted = false;
    compare(presentation.outputIcon, "speaker");
    compare(presentation.inputIcon, "mic");
    compare(presentation.accent, colors.info);
  }

  function test_audio_replacement() {
    presentation.current = { muted: true, volume: 0.72 };
    compare(presentation.outputIcon, "mute");
    compare(presentation.inputIcon, "mic-off");
    compare(presentation.accent, colors.danger);
    presentation.current = null;
    compare(presentation.outputIcon, "speaker");
    compare(presentation.inputIcon, "mic");
    compare(presentation.accent, colors.info);
    presentation.current = audio;
    audio.muted = true;
    compare(presentation.outputIcon, "mute");
  }
}
