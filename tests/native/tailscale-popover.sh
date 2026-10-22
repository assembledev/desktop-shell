#!/usr/bin/env bash
set -euo pipefail
source_root="$(cd -- "${BASH_SOURCE[0]%/*}/../.." && pwd)"
if [ -z "${WAYLAND_DISPLAY:-}" ]; then exit 77; fi
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT
cp -R "$source_root/src/modules" "$test_root/modules"
cp "$source_root/tests/native/tailscale-popover.qml" "$test_root/shell.qml"
mkdir "$test_root/files"
printf 'fixture\n' >"$test_root/files/example.txt"
sed -i "s@currentFolder: StandardPaths.standardLocations(StandardPaths.HomeLocation)\[0\]@currentFolder: \"file://$test_root/files\"@" "$test_root/modules/tailscale/TailscaleDetails.qml"
printf '#!%s\n' "$(command -v bash)" >"$test_root/backend"
cat >>"$test_root/backend" <<'SH'
set -eu
case "$2" in
  file-info)
    file="$3"
    jq -nc --arg path "$file" --argjson size "$(stat -c '%s' -- "$file")" '[{path:$path,name:"example.txt",size:$size}]'
    ;;
  send-file) exec sleep 0.5 ;;
  *) exit 2 ;;
esac
SH
chmod +x "$test_root/backend"
export DESKTOP_SHELL_TEST_BACKEND="$test_root/backend"
QT_QPA_PLATFORM=wayland timeout --kill-after=1s 12s quickshell --no-color --path "$test_root/shell.qml"
