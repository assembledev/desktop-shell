#!/usr/bin/env bash
set -euo pipefail
source_root="$(cd -- "${BASH_SOURCE[0]%/*}/../.." && pwd)"
command -v notify-send >/dev/null
command -v dbus-run-session >/dev/null
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT
cp "$source_root/src/modules/tailscale/"{TailscaleStatus.js,TaildropNotifications.qml} "$test_root/"
cp "$source_root/tests/native/taildrop-notification.qml" "$test_root/shell.qml"
mkdir -m 700 "$test_root/runtime" "$test_root/data" "$test_root/user-data"
# No service directories: host portals must never autostart on the test bus.
cat >"$test_root/dbus.conf" <<'CONF'
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN" "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>session</type>
  <listen>unix:tmpdir=/tmp</listen>
  <policy context="default">
    <allow own="*"/>
    <allow send_destination="*"/>
    <allow receive_sender="*"/>
  </policy>
</busconfig>
CONF
env -u WAYLAND_DISPLAY -u DISPLAY \
  QT_QPA_PLATFORM=offscreen XDG_RUNTIME_DIR="$test_root/runtime" \
  XDG_DATA_DIRS="$test_root/data" XDG_DATA_HOME="$test_root/user-data" \
  timeout --kill-after=1s 8s dbus-run-session --config-file="$test_root/dbus.conf" -- quickshell --no-color --path "$test_root/shell.qml"
