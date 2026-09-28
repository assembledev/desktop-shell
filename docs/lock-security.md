# Session-lock security

The lock runs separately from the desktop shell and uses Wayland's
`ext-session-lock-v1` through Quickshell `WlSessionLock`. The compositor owns
input isolation and output coverage; the QML view is not the security boundary.
The lock releases only after `PamContext` reports success for
`desktop-shell-lock`. Its IPC exposes lock, focus, and status, with no unlock
method. Lock preview and the greetd login view do not own a session lock.

`desktop-shell lock status` reports compositor acknowledgement (`secure`), not
merely the requested state (`locked`). The lock command waits for acknowledgement
and returns failure if it remains unconfirmed for 10 seconds after starting the
service. A failure must not be treated as permission to leave the session
unattended. The timeout does not terminate the locker; a slow lock may still
complete afterward.

## System integration

The host must provide the PAM service, lock triggers, and suspend coordination.
The shell does not install an inactivity-lock policy. Display dimming and DPMS
off do not lock a session. Configure an explicit lock timeout in the host's idle
manager if unattended sessions must lock automatically.

For Hypridle, `lock_cmd` handles session-lock requests, `before_sleep_cmd` starts
the lock, and `inhibit_sleep = 3` waits for compositor lock notification. Keep the
system's finite suspend-inhibitor timeout in mind: a broken locker cannot promise
safe suspend indefinitely. Test failure paths and resume on the actual host.

Authentication delay and account lockout are PAM policy. The default NixOS
integration uses the system's PAM defaults; the UI's “too many attempts” message
does not itself enforce a cross-attempt lockout. This frontend expects a password
conversation; arbitrary multi-factor PAM conversations need separate UI support.

## Threat boundaries and recovery

- A conforming compositor keeps the session locked if the locker crashes or is
  killed. That is an availability failure, not an automatic unlock. Restarting
  the ordinary desktop shell must not release the lock.
- Hyprland's `misc.allow_session_lock_restore` permits a replacement lock client
  after a crash. Recovery still depends on trusting processes with access to the
  user's Wayland connection. This is not protection from code already running as
  that user, a logged-in text console, remote access as that user, or root.
- Switching to a text console does not authenticate that console. An already
  authenticated console is a separate access path and is not covered by a
  Wayland session lock.
- Disk encryption protects stored data when its keys are unavailable. A running
  or suspended session retains secrets in memory. Firmware, boot-chain integrity,
  hardware attacks, and kernel/compositor vulnerabilities are outside this UI's
  protection. An unencrypted boot partition needs an independently verified boot
  integrity mechanism to resist tampering.

If the locker dies, recover through an authenticated administrative channel.
Restarting the locker requires compositor support for lock restoration; otherwise
ending the graphical session loses unsaved work. Do not configure an unauthenticated
recovery shortcut that releases the compositor lock.

## Validation

Backend regression tests exercise delayed acknowledgement, timeout, an existing
secure lock, and service-start failure. QML checks verify the source API contract.
They do not prove compositor enforcement. In a disposable compositor session,
verify wrong and correct passwords, locker termination, output hotplug, and input
isolation. Suspend/resume and hardware attack resistance require host testing.

Protocol references: [Wayland session lock](https://wayland.app/protocols/ext-session-lock-v1),
[Quickshell WlSessionLock](https://quickshell.org/docs/v0.2.1/types/Quickshell.Wayland/WlSessionLock/),
and [Hypridle](https://wiki.hypr.land/Hypr-Ecosystem/hypridle/).
