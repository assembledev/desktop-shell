import QtQuick
import Quickshell

QtObject {
  id: root

  readonly property var values: {
    const fallback = {
      bgSolid: "#151725",
      bgRaised: "#23283b",
      bgMuted: "#1c2030",
      bgHover: "#303650",
      bgHoverAlt: "#2a3047",
      bgToast: "#191c2b",
      selectedBg: "#3a4060",
      textPrimary: "#eef0f8",
      textSecondary: "#c7ccdc",
      textMuted: "#929cb2",
      textDisabled: "#69748b",
      textOnAccent: "#151725",
      accent: "#a78bfa",
      accentHover: "#c4b5fd",
      info: "#67d4e8",
      special: "#d08cf3",
      resource: "#9ece6a",
      utility: "#f0c36e",
      success: "#9ece6a",
      warning: "#f0c36e",
      caution: "#f3a66e",
      danger: "#f283a2",
      dangerStrong: "#ff7898",
      border: "#424a68",
      borderMuted: "#343b55",
      surfaceGlass: "#bf151725",
      surfaceGlassStrong: "#ca151725",
      surfaceScrim: "#46151725",
      surface: "#cc151725",
      surfaceBar: "#c2151725",
      surfaceRaised: "#b823283b",
      surfaceSoft: "#9f23283b",
      surfaceHover: "#bd303650",
      surfaceMuted: "#ad1c2030",
      surfaceMutedHover: "#bc2a3047",
      surfaceAccent: "#38151725",
      surfaceToast: "#d8191c2b",
      borderSubtle: "#70424a68",
      fontFamily: "FiraCode Nerd Font"
    };

    const raw = Quickshell.env("DESKTOP_SHELL_THEME_JSON");
    if (!raw)
      return fallback;
    try {
      const supplied = JSON.parse(raw);

      // Normalize the pre-semantic palette at the raw environment boundary.
      if (supplied.textPrimary === undefined && supplied.foreground !== undefined)
        supplied.textPrimary = supplied.foreground;
      if (supplied.textSecondary === undefined && supplied.text !== undefined)
        supplied.textSecondary = supplied.text;
      if (supplied.textMuted === undefined && supplied.mutedAlt !== undefined)
        supplied.textMuted = supplied.mutedAlt;
      if (supplied.textDisabled === undefined && supplied.muted !== undefined)
        supplied.textDisabled = supplied.muted;
      if (supplied.accent === undefined && supplied.terminalBlue !== undefined)
        supplied.accent = supplied.terminalBlue;
      if (supplied.info === undefined && supplied.blue !== undefined)
        supplied.info = supplied.blue;
      if (supplied.success === undefined && supplied.green !== undefined)
        supplied.success = supplied.green;
      if (supplied.warning === undefined && supplied.yellow !== undefined)
        supplied.warning = supplied.yellow;
      if (supplied.caution === undefined && supplied.orange !== undefined)
        supplied.caution = supplied.orange;
      if (supplied.danger === undefined && supplied.red !== undefined)
        supplied.danger = supplied.red;
      if (supplied.dangerStrong === undefined && supplied.brightRed !== undefined)
        supplied.dangerStrong = supplied.brightRed;
      if (supplied.special === undefined && supplied.purple !== undefined)
        supplied.special = supplied.purple;

      return Object.assign({}, fallback, supplied);
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
  readonly property color selectedBg: values.selectedBg

  readonly property color textPrimary: values.textPrimary
  readonly property color textSecondary: values.textSecondary
  readonly property color textMuted: values.textMuted
  readonly property color textDisabled: values.textDisabled
  readonly property color textOnAccent: values.textOnAccent

  readonly property color iconPrimary: textPrimary
  readonly property color iconSecondary: textSecondary
  readonly property color iconMuted: textMuted
  readonly property color iconAccent: accent

  readonly property color accent: values.accent
  readonly property color accentHover: values.accentHover
  readonly property color info: values.info
  readonly property color special: values.special
  readonly property color resource: values.resource
  readonly property color utility: values.utility
  readonly property color success: values.success
  readonly property color warning: values.warning
  readonly property color caution: values.caution
  readonly property color danger: values.danger
  readonly property color dangerStrong: values.dangerStrong

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

  readonly property color border: values.border
  readonly property color borderMuted: values.borderMuted
  readonly property color borderSubtle: values.borderSubtle
  readonly property string fontFamily: values.fontFamily

  // Runtime aliases keep direct QML consumers source-compatible while the
  // shell itself uses only semantic roles.
  readonly property color foreground: textPrimary
  readonly property color text: textSecondary
  readonly property color muted: textDisabled
  readonly property color mutedAlt: textMuted
  readonly property color blue: info
  readonly property color terminalBlue: accent
  readonly property color green: success
  readonly property color yellow: warning
  readonly property color orange: caution
  readonly property color red: danger
  readonly property color brightRed: dangerStrong
  readonly property color purple: special
}
