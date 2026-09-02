let
  withAlpha = alpha: color: "#${alpha}${builtins.substring 1 6 color}";

  bgSolid = "#151725";
  bgRaised = "#23283b";
  bgMuted = "#1c2030";
  bgHover = "#303650";
  bgHoverAlt = "#2a3047";
  bgToast = "#191c2b";
  selectedBg = "#3a4060";
  accent = "#a78bfa";
  border = "#424a68";
in
{
  inherit
    accent
    bgHover
    bgHoverAlt
    bgMuted
    bgRaised
    bgSolid
    bgToast
    border
    selectedBg
    ;

  fontFamily = "FiraCode Nerd Font";

  # Content hierarchy. Chromatic colors are deliberately excluded here.
  textPrimary = "#eef0f8";
  textSecondary = "#c7ccdc";
  textMuted = "#929cb2";
  textDisabled = "#69748b";
  textOnAccent = bgSolid;

  # Navigation, domains, and state share one luminous aurora family. Domain
  # accents belong on compact anchors such as icons and badges, not body text.
  accentHover = "#c4b5fd";
  info = "#67d4e8";
  special = "#d08cf3";
  resource = "#9ece6a";
  utility = "#f0c36e";
  success = "#9ece6a";
  warning = "#f0c36e";
  caution = "#f3a66e";
  danger = "#f283a2";
  dangerStrong = "#ff7898";

  borderMuted = "#343b55";
  borderSubtle = withAlpha "70" border;

  surfaceGlass = withAlpha "bf" bgSolid;
  surfaceGlassStrong = withAlpha "ca" bgSolid;
  surfaceScrim = withAlpha "46" bgSolid;
  surface = withAlpha "cc" bgSolid;
  surfaceBar = withAlpha "c2" bgSolid;
  surfaceRaised = withAlpha "b8" bgRaised;
  surfaceSoft = withAlpha "9f" bgRaised;
  surfaceHover = withAlpha "bd" bgHover;
  surfaceMuted = withAlpha "ad" bgMuted;
  surfaceMutedHover = withAlpha "bc" bgHoverAlt;
  surfaceAccent = withAlpha "38" bgSolid;
  surfaceToast = withAlpha "d8" bgToast;
}
