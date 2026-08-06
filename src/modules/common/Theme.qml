import QtQuick
import Quickshell

QtObject {
  id: root

  readonly property var values: {
    const fallback = {
      bgSolid: "#1a1b26",
      bgRaised: "#242940",
      bgMuted: "#24283b",
      bgHover: "#343b5f",
      bgHoverAlt: "#2f354f",
      bgToast: "#1b1f31",
      foreground: "#c0caf5",
      text: "#cfc9c2",
      muted: "#565f89",
      mutedAlt: "#7c819f",
      selectedBg: "#414868",
      blue: "#7dcfff",
      terminalBlue: "#7aa2f7",
      green: "#9ece6a",
      yellow: "#e0af68",
      orange: "#ff9e64",
      red: "#f7768e",
      brightRed: "#ff7a93",
      purple: "#bb9af7",
      surfaceGlass: "#bf1a1b26",
      surfaceGlassStrong: "#ca1a1b26",
      surfaceScrim: "#461a1b26",
      surface: "#cc1a1b26",
      surfaceBar: "#c21a1b26",
      surfaceRaised: "#b8242940",
      surfaceSoft: "#9f242940",
      surfaceHover: "#bd343b5f",
      surfaceMuted: "#ad24283b",
      surfaceMutedHover: "#bc2f354f",
      surfaceAccent: "#381a1b26",
      surfaceToast: "#d81b1f31",
      borderSubtle: "#70414868",
      fontFamily: "FiraCode Nerd Font"
    };

    const raw = Quickshell.env("DESKTOP_SHELL_THEME_JSON");
    if (!raw)
      return fallback;
    try {
      return Object.assign({}, fallback, JSON.parse(raw));
    } catch (error) {
      console.error("theme: invalid DESKTOP_SHELL_THEME_JSON: " + error);
      return fallback;
    }
  }

  readonly property color bgSolid: values.bgSolid
  readonly property color bgRaised: values.bgRaised
  readonly property color bgMuted: values.bgMuted
  readonly property color bgHover: values.bgHover
  readonly property color bgHoverAlt: values.bgHoverAlt
  readonly property color bgToast: values.bgToast
  readonly property color foreground: values.foreground
  readonly property color text: values.text
  readonly property color muted: values.muted
  readonly property color mutedAlt: values.mutedAlt
  readonly property color selectedBg: values.selectedBg
  readonly property color blue: values.blue
  readonly property color terminalBlue: values.terminalBlue
  readonly property color green: values.green
  readonly property color yellow: values.yellow
  readonly property color orange: values.orange
  readonly property color red: values.red
  readonly property color brightRed: values.brightRed
  readonly property color purple: values.purple

  readonly property color surfaceGlass: values.surfaceGlass
  readonly property color surfaceGlassStrong: values.surfaceGlassStrong
  readonly property color surfaceScrim: values.surfaceScrim
  readonly property color surface: values.surface
  readonly property color surfaceBar: values.surfaceBar
  readonly property color surfaceRaised: values.surfaceRaised
  readonly property color surfaceSoft: values.surfaceSoft
  readonly property color surfaceHover: values.surfaceHover
  readonly property color surfaceMuted: values.surfaceMuted
  readonly property color surfaceMutedHover: values.surfaceMutedHover
  readonly property color surfaceAccent: values.surfaceAccent
  readonly property color surfaceToast: values.surfaceToast

  readonly property color border: muted
  readonly property color borderMuted: selectedBg
  readonly property color borderSubtle: values.borderSubtle
  readonly property string fontFamily: values.fontFamily
}
