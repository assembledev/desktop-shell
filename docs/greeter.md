# Login greeter

The optional greetd greeter uses Desktop Shell's lock-screen presentation for
login. It authenticates one configured local account and starts Hyprland
through UWSM. Enable it after the ordinary shell works in your existing session.

Add this to your NixOS configuration:

```nix
programs.desktop-shell = {
  enable = true;
  greeter = {
    enable = true;
    user = "your-user";
    scale = 1.25;
  };
};
```

Replace `your-user` with an existing account. Disable the current display
manager in the same configuration change. The module enables greetd and runs
the greeter on VT1.

## Options

All options below are under `programs.desktop-shell.greeter`:

| Option | Default | Purpose |
| --- | --- | --- |
| `user` | `""` | Local account used for login; required when enabled |
| `scale` | `1` | UI scale factor |
| `wallpaperPath` | `""` | Absolute image path readable by the `greeter` user |
| `outputMode` | `"last"` | Use Cage's final discovered output, or `"extend"` to span outputs |
| `cursorPackage` | `pkgs.bibata-cursors` | Package containing the cursor theme |
| `cursorTheme` | `"Bibata-Modern-Ice"` | Cursor theme name |
| `sessionCommand` | UWSM Hyprland launch | Command argv run after authentication |
| `theme` | Built-in palette | Theme values for the login view |

The greeter uses an English locale and US keyboard layout. Cursor size starts
at 24 px and follows `scale`. User-session Home Manager theme overrides apply
to the shell; set `greeter.theme` for the login screen.

For a wallpaper, use a system-readable image, for example:

```nix
{
  environment.etc."desktop-shell/wallpaper.jpg".source = ./wallpaper.jpg;
  programs.desktop-shell.greeter.wallpaperPath = "/etc/desktop-shell/wallpaper.jpg";
}
```

After ten minutes without input, the greeter clears unfinished password input
and blanks the screen. Input wakes it; the first key or click is consumed.
This blanks the login view while keeping the display link active. The logged-in
session has its own idle and display-power policy.

## Logs and recovery

```console
$ journalctl -b -u greetd.service
$ journalctl -b -t desktop-shell-greeter
```

The first command shows greetd; the second includes Quickshell and Cage output.
If login fails, use an authenticated text console to inspect the journal and
restore your previous login configuration.

See [greetd on the NixOS Wiki](https://wiki.nixos.org/wiki/Greetd) for the login
manager and [UWSM](https://wiki.hypr.land/useful-utilities/uwsm/) for session setup.
