let
  withAlpha = alpha: color: "#${alpha}${builtins.substring 1 6 color}";
  bgSolid = "#1a1b26";
  bgRaised = "#242940";
  bgMuted = "#24283b";
  bgHover = "#343b5f";
  bgHoverAlt = "#2f354f";
  bgToast = "#1b1f31";
  selectedBg = "#414868";
in
{
  inherit
    bgHover
    bgHoverAlt
    bgMuted
    bgRaised
    bgSolid
    bgToast
    selectedBg
    ;

  foreground = "#c0caf5";
  fontFamily = "FiraCode Nerd Font";
  text = "#cfc9c2";
  muted = "#565f89";
  mutedAlt = "#7c819f";
  blue = "#7dcfff";
  terminalBlue = "#7aa2f7";
  green = "#9ece6a";
  yellow = "#e0af68";
  orange = "#ff9e64";
  red = "#f7768e";
  brightRed = "#ff7a93";
  purple = "#bb9af7";

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
  borderSubtle = withAlpha "70" selectedBg;
}
