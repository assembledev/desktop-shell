#!/usr/bin/env bash
set -euo pipefail
source_root="$(cd -- "${BASH_SOURCE[0]%/*}/../.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT
cp -R "$source_root/src/modules" "$test_root/modules"
cp "$source_root/tests/native/clipboard-actions.qml" "$test_root/shell.qml"
# Only the layer container needs Wayland; keep the production action/state logic.
python3 - "$test_root/modules/clipboard_history/ClipboardHistory.qml" <<'PYTHON'
from pathlib import Path
import sys
path = Path(sys.argv[1])
source = path.read_text()
start = source.index("  PanelWindow {\n")
end = source.index("    InputIntent {", start)
source = source[:start] + "  Window {\n    id: window\n    visible: false\n    width: 800\n    height: 700\n\n" + source[end:]
path.write_text(source)
PYTHON
printf '#!%s\n' "$(command -v bash)" >"$test_root/backend"
cat >>"$test_root/backend" <<'BACKEND'
set -eu
case "$2" in
  list-json) printf '[]\n' ;;
  wipe) printf 'wipe\n' >>"$TEST_ACTION_LOG" ;;
esac
BACKEND
chmod +x "$test_root/backend"
export DESKTOP_SHELL_BACKEND="$test_root/backend"
export TEST_ACTION_LOG="$test_root/actions"
: >"$TEST_ACTION_LOG"
mkdir -m 700 "$test_root/runtime" "$test_root/data" "$test_root/user-data" "$test_root/home" "$test_root/config" "$test_root/state"
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
env -u WAYLAND_DISPLAY -u DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE -u DESKTOP_SHELL_CONFIG \
  HOME="$test_root/home" XDG_CONFIG_HOME="$test_root/config" XDG_STATE_HOME="$test_root/state" \
  QT_QPA_PLATFORM=offscreen XDG_RUNTIME_DIR="$test_root/runtime" \
  XDG_DATA_DIRS="$test_root/data" XDG_DATA_HOME="$test_root/user-data" \
  timeout --kill-after=1s 8s dbus-run-session --config-file="$test_root/dbus.conf" -- quickshell --no-color --path "$test_root/shell.qml"
test "$(cat "$TEST_ACTION_LOG")" = wipe
