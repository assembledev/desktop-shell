#!/usr/bin/env bash
set -euo pipefail
source_root="${1:?source root is required}"
# shellcheck source=../src/backend/lib/session.sh
source "$source_root/src/backend/lib/session.sh"
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT

ensure_hypr_env() { :; }
hyprctl() { printf '%s\n' "$device_json"; }
device_json='{"keyboards":[{"main":true,"name":"test","layout":"us,ru","active_layout_index":1}]}'
keyboard_json | jq -e '.name == "test" and .index == 1' >/dev/null
device_json='{"keyboards":[]}'
keyboard_json | jq -e '.index == -1' >/dev/null
device_json='invalid'
keyboard_json | jq -e '.name == "" and .layout == "" and .index == -1' >/dev/null

# Exercise the real IPC wrapper against an unresponsive client.
mkdir -p "$test_root/bin"
# Runtime-generated scripts are not processed by Nix's patchShebangs hook.
printf '#!%s\nexec sleep 5\n' "$(command -v bash)" >"$test_root/bin/quickshell"
chmod +x "$test_root/bin/quickshell"
if (
  export PATH="$test_root/bin:$PATH"
  export DESKTOP_SHELL_QML="$source_root/src"
  lock_ipc status 0.05
); then
  printf 'unresponsive IPC did not time out\n' >&2
  exit 1
else
  test "$?" = 124
fi

# The initial status request shares the confirmation budget with lock startup.
lock_start() { touch "$test_root/started"; }
if (
  export PATH="$test_root/bin:$PATH"
  export DESKTOP_SHELL_QML="$source_root/src"
  lock_confirmation_timeout_seconds=1
  lock_screen lock 2>"$test_root/error"
); then
  printf 'unresponsive lock command returned success\n' >&2
  exit 1
fi
test ! -e "$test_root/started"
grep -F 'not confirmed' "$test_root/error" >/dev/null

# Test the command's acknowledgement contract without touching a compositor.
lock_start() { touch "$test_root/started"; }
sleep() { SECONDS=$((SECONDS + 1)); }
lock_ipc() {
  if [ "$1" = focus ]; then
    touch "$test_root/focused"
    return
  fi
  count="$(cat "$test_root/count")"
  printf '%s\n' "$((count + 1))" >"$test_root/count"
  if [ "$count" -ge "$secure_after" ]; then
    printf 'true\n'
  else
    printf 'false\n'
  fi
}

printf '0\n' >"$test_root/count"
secure_after=3
lock_screen lock
test -f "$test_root/started"
test "$(cat "$test_root/count")" -ge 4

rm "$test_root/started"
printf '0\n' >"$test_root/count"
secure_after=0
lock_screen lock
test ! -f "$test_root/started"
test -f "$test_root/focused"

printf '0\n' >"$test_root/count"
secure_after=1000
if lock_screen lock 2>"$test_root/error"; then
  printf 'lock returned success without compositor acknowledgement\n' >&2
  exit 1
fi
grep -F 'not confirmed' "$test_root/error" >/dev/null

lock_start() { return 1; }
printf '0\n' >"$test_root/count"
if lock_screen lock; then
  printf 'lock ignored a failed service start\n' >&2
  exit 1
fi
