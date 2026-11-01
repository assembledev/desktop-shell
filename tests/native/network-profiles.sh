#!/usr/bin/env bash
set -euo pipefail
source_root="$(cd -- "${BASH_SOURCE[0]%/*}/../.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT
cp -R "$source_root/src/modules" "$test_root/modules"
cp "$source_root/tests/native/network-profiles.qml" "$test_root/shell.qml"
printf '#!%s\n' "$(command -v bash)" >"$test_root/backend"
cat >>"$test_root/backend" <<'SH'
set -eu
case "$2" in
  status)
    count=$(cat "$TEST_NETWORK_STATE/polls")
    printf '%s' "$((count + 1))" >"$TEST_NETWORK_STATE/polls"
    snapshot=$(cat "$TEST_NETWORK_STATE/status.json")
    case "$count" in 0) sleep 0.3 ;; 1) sleep 0.4 ;; esac
    printf '%s' "$snapshot"
    ;;
  select)
    printf 'select %s\n' "$4" >>"$TEST_NETWORK_STATE/actions"
    jq --arg id "$4" '.selectedProfile = $id' "$TEST_NETWORK_STATE/status.json" >"$TEST_NETWORK_STATE/next.json"
    mv "$TEST_NETWORK_STATE/next.json" "$TEST_NETWORK_STATE/status.json"
    sleep 0.1
    if [ ! -e "$TEST_NETWORK_STATE/retried" ]; then
      touch "$TEST_NETWORK_STATE/retried"
      printf 'fixture selection failed\n' >&2
      exit 1
    fi
    ;;
  toggle) printf 'toggle\n' >>"$TEST_NETWORK_STATE/actions" ;;
  *) exit 2 ;;
esac
SH
chmod +x "$test_root/backend"
printf '{"bar":{"networkControls":[{"id":"private","label":"Private","selectCommand":["fixture-select"]}]}}\n' >"$test_root/config.json"
printf '{"active":false,"profiles":[{"id":"north","label":"North"},{"id":"south","label":"South"}],"selectedProfile":"north"}\n' >"$test_root/status.json"
printf 0 >"$test_root/polls"
export TEST_NETWORK_STATE="$test_root"
export DESKTOP_SHELL_TEST_BACKEND="$test_root/backend"
export DESKTOP_SHELL_TEST_CONFIG="$test_root/config.json"
QT_QPA_PLATFORM=offscreen timeout --kill-after=1s 10s quickshell --no-color --path "$test_root/shell.qml"
test "$(cat "$test_root/actions")" = $'select south\nselect south'
if [ -n "${WAYLAND_DISPLAY:-}" ]; then
  jq '.selectedProfile = "north" | .fixtureSnapshot = true' "$test_root/status.json" >"$test_root/next.json"
  mv "$test_root/next.json" "$test_root/status.json"
  printf 0 >"$test_root/polls"
  cp "$source_root/tests/native/network-profiles-popover.qml" "$test_root/shell.qml"
  QT_QPA_PLATFORM=wayland timeout --kill-after=1s 10s quickshell --no-color --path "$test_root/shell.qml"
fi
