{
  workspaces = {
    items = [
      {
        id = 1;
        label = "I";
        x = 0;
        y = 0;
      }
      {
        id = 2;
        label = "II";
        x = 1;
        y = 0;
      }
      {
        id = 3;
        label = "III";
        x = 2;
        y = 0;
      }
      {
        id = 4;
        label = "IV";
        x = 3;
        y = 0;
      }
      {
        id = 5;
        label = "V";
        x = 4;
        y = 0;
      }
    ];
    scrolling = null;
  };

  output = null;

  display.startupLayout = [ ];

  wallpaper = {
    directory = null;
    default = null;
  };

  bar = {
    compact = false;
    showVram = true;
    workspaceIcons = true;
    networkControls = [ ];
  };

  keyboard.layoutLabels = [ "EN" ];

  browserTabs = {
    enable = false;
    desktopEntryId = "firefox";
    displayName = "Firefox";
    icon = "firefox";
  };

  lock.keyboardLayoutIndex = null;

  integrations = {
    hotkeys = [ ];
    privilegedHelper = null;
    recordingStateFile = null;
    sddmWallpaperSync = null;
  };

  theme = import ./theme.nix;
}
