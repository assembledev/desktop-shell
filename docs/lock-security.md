# Session lock

The lock runs separately from the desktop shell. It uses Quickshell's
`WlSessionLock` and Wayland's `ext-session-lock-v1`; Hyprland owns input isolation
and output coverage. PAM authenticates the account through
`desktop-shell-lock`. The NixOS module creates that PAM service.

`desktop-shell lock` waits for compositor acknowledgement and returns failure
if it remains unconfirmed within ten seconds. `desktop-shell lock status`
prints `true` only after confirmation. A timeout leaves the locker running, so
a slow lock may still complete. Run `desktop-shell lock status` to check it.

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

Password delay and account lockout follow the system's PAM policy. The view
supports password conversations; custom multi-factor PAM flows need additional
UI support.

## Recovery

Restarting the desktop shell leaves the lock in place. Hyprland keeps a locked
session locked if its locker crashes. Its `misc.allow_session_lock_restore`
setting permits a replacement lock client after a crash.

Log in through a text console or SSH to inspect the locker:

```console
$ journalctl --user -b -u desktop-lock.service
```

After a locker crash, run `desktop-shell lock` again if Hyprland permits a
replacement lock client. Ending the graphical session also releases the lock,
but loses unsaved work.

Protocol references: [Wayland session lock](https://wayland.app/protocols/ext-session-lock-v1)
and [Quickshell WlSessionLock](https://quickshell.org/docs/v0.3.0/types/Quickshell.Wayland/WlSessionLock/).
