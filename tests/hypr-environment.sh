#!/usr/bin/env bash
set -euo pipefail
source_root="${1:?source root is required}"
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT
mkdir -p "$test_root/bin" "$test_root/runtime/hypr/aaa-live" "$test_root/runtime/hypr/zzz-stale"
export XDG_RUNTIME_DIR="$test_root/runtime"
export HYPR_ENV_FIXTURE="$test_root/instances.json" HYPR_ENV_CALLS="$test_root/calls"
export HYPR_ENV_LIVE='aaa-live bbb-live' HYPR_ENV_HANG=''
printf '#!%s\n' "$(command -v bash)" >"$test_root/bin/hyprctl"
cat >>"$test_root/bin/hyprctl" <<'MOCK'
set -eu
printf '%s\n' "$*" >>"$HYPR_ENV_CALLS"
case "$*" in
  '-j instances') cat "$HYPR_ENV_FIXTURE" ;;
  '-i '*' version')
    if [ "$2" = "$HYPR_ENV_HANG" ]; then sleep 10; fi
    case " $HYPR_ENV_LIVE " in *" $2 "*) exit 0 ;; *) exit 1 ;; esac
    ;;
  *) exit 2 ;;
esac
MOCK
chmod +x "$test_root/bin/hyprctl"
export PATH="$test_root/bin:$PATH"
# shellcheck source=../src/backend/lib/hypr-environment.sh
source "$source_root/src/backend/lib/hypr-environment.sh"

one='[{"instance":"aaa-live","wl_socket":"wayland-9"},{"instance":"zzz-stale","wl_socket":"wayland-0"}]'
two='[{"instance":"aaa-live","wl_socket":"wayland-9"},{"instance":"bbb-live","wl_socket":"wayland-2"}]'
printf '%s\n' "$one" >"$HYPR_ENV_FIXTURE"
unset HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY
ensure_hypr_env
test "$HYPRLAND_INSTANCE_SIGNATURE" = aaa-live
test "$WAYLAND_DISPLAY" = wayland-9
grep -Fx -- '-i aaa-live version' "$HYPR_ENV_CALLS" >/dev/null

printf '%s\n' "$two" >"$HYPR_ENV_FIXTURE"
for known in signature display absolute-display; do
  unset HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY
  case "$known" in
    signature) export HYPRLAND_INSTANCE_SIGNATURE=bbb-live ;;
    display) export WAYLAND_DISPLAY=wayland-2 ;;
    absolute-display) export WAYLAND_DISPLAY="$XDG_RUNTIME_DIR/wayland-2" ;;
  esac
  ensure_hypr_env
  test "$HYPRLAND_INSTANCE_SIGNATURE" = bbb-live
  test "${WAYLAND_DISPLAY##*/}" = wayland-2
done

for failure in ambiguous wrong-display wrong-signature none malformed dead timeout; do
  unset HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY
  printf '%s\n' "$two" >"$HYPR_ENV_FIXTURE"
  export HYPR_ENV_LIVE='aaa-live bbb-live' HYPR_ENV_HANG=''
  case "$failure" in
    wrong-display) export WAYLAND_DISPLAY=wayland-missing ;;
    wrong-signature) export HYPRLAND_INSTANCE_SIGNATURE=missing ;;
    none) printf '[]\n' >"$HYPR_ENV_FIXTURE" ;;
    malformed) printf 'not-json\n' >"$HYPR_ENV_FIXTURE" ;;
    dead) export HYPR_ENV_LIVE='' ;;
    timeout)
      printf '%s\n' "$one" >"$HYPR_ENV_FIXTURE"
      export HYPR_ENV_HANG=aaa-live HYPR_ENV_LIVE=''
      ;;
  esac
  before_signature="${HYPRLAND_INSTANCE_SIGNATURE:-}"
  before_display="${WAYLAND_DISPLAY:-}"
  if ensure_hypr_env >"$test_root/output" 2>"$test_root/error"; then
    printf 'environment discovery must fail for %s\n' "$failure" >&2
    exit 1
  fi
  test "${HYPRLAND_INSTANCE_SIGNATURE:-}" = "$before_signature"
  test "${WAYLAND_DISPLAY:-}" = "$before_display"
  test -s "$test_root/error"
done

# A complete session environment is authoritative and needs no discovery.
export HYPRLAND_INSTANCE_SIGNATURE=explicit WAYLAND_DISPLAY=explicit-display
: >"$HYPR_ENV_CALLS"
ensure_hypr_env
test ! -s "$HYPR_ENV_CALLS"

# Discovery failures must stop runtime commands even inside an if condition,
# where Bash disables implicit errexit handling in called functions.
# shellcheck source=../src/backend/lib/commands.sh
source "$source_root/src/backend/lib/commands.sh"
export HYPR_ENV_UNEXPECTED="$test_root/unexpected-ipc"
printf '#!%s\n' "$(command -v bash)" >"$test_root/bin/quickshell"
cat >>"$test_root/bin/quickshell" <<'MOCK'
touch "$HYPR_ENV_UNEXPECTED"
printf '{}\n'
MOCK
chmod +x "$test_root/bin/quickshell"
unset HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY
printf '%s\n' "$two" >"$HYPR_ENV_FIXTURE"
export HYPR_ENV_LIVE='aaa-live bbb-live' HYPR_ENV_HANG=''
if runtime_json test status >/dev/null 2>&1; then
  printf 'ambiguous environment must stop runtime IPC\n' >&2
  exit 1
fi
test ! -e "$test_root/unexpected-ipc"
printf 'PASS compositor environment discovery\n'
