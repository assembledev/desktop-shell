# Session lock

The lock runs separately from the desktop shell. It uses Quickshell's
`WlSessionLock` and Wayland's `ext-session-lock-v1`; Hyprland owns input isolation
and output coverage. PAM authenticates the account through
`desktop-shell-lock`. The NixOS module creates that PAM service.

`desktop-shell lock` waits for compositor acknowledgement and returns failure
if it remains unconfirmed within ten seconds. `desktop-shell lock status`
prints `true` only after confirmation. A timeout leaves the locker running, so
a slow lock may still complete. Check the screen before leaving the session.

## System integration

The shell supplies the lock command. Configure its triggers through your idle
manager. For Hypridle, add this to Home Manager:

```nix
{ config, lib, ... }:
let
  lock = "${lib.getExe config.programs.desktop-shell.finalPackage} lock";
in
{
  services.hypridle = {
    enable = true;
    settings.general = {
      lock_cmd = lock;
      before_sleep_cmd = lock;
      inhibit_sleep = 3;
    };
  };
}
```

This handles session-lock requests and locks before sleep. Mode `3` waits for
Hyprland's lock notification before releasing the sleep inhibitor. Add a
Hypridle `listener` with your chosen timeout for inactivity locking; display
blanking and DPMS are separate actions. See the
[Hypridle guide](https://wiki.hypr.land/hypr-ecosystem/user/hypridle/) for listener
configuration. Test lock, unlock, and suspend/resume after setting it up.

The locker uses the requesting session's runtime directory, Wayland display,
and Hyprland instance, so an old systemd activation environment does not select
a different session. Password delay and account lockout follow the system's
PAM policy. The view supports password conversations; custom multi-factor PAM
flows need additional UI support.

## Recovery

Restarting the desktop shell leaves the lock in place. Hyprland keeps a locked
session locked if its locker crashes. Its `misc.allow_session_lock_restore`
setting permits a replacement lock client after a crash.

Use an already authenticated text console or administrative connection to
inspect `journalctl --user -b -u desktop-lock.service`. Recovery with a
replacement locker depends on compositor support; ending the graphical session
loses unsaved work. Keep recovery access authenticated.

Protocol references: [Wayland session lock](https://wayland.app/protocols/ext-session-lock-v1)
and [Quickshell WlSessionLock](https://quickshell.org/docs/v0.2.1/types/Quickshell.Wayland/WlSessionLock/).
