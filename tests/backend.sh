#!/usr/bin/env bash

set -euo pipefail

source_root="${1:?source root is required}"
default_config="${2:?default config is required}"
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT

export HOME="$test_root/home"
export XDG_CONFIG_HOME="$test_root/config"
export XDG_STATE_HOME="$test_root/state"
export XDG_RUNTIME_DIR="$test_root/runtime"
export DESKTOP_SHELL_DEFAULT_CONFIG="$default_config"
export DESKTOP_SHELL_SYS_ROOT="$test_root/sys"
export DESKTOP_SHELL_PROC_ROOT="$test_root/proc"
export DESKTOP_SHELL_EXECUTABLE=desktop-shell
export DESKTOP_SHELL_QML="$source_root/src"
mkdir -p "$HOME" "$XDG_RUNTIME_DIR" "$DESKTOP_SHELL_SYS_ROOT/class/backlight" "$DESKTOP_SHELL_PROC_ROOT"
mkdir -p "$XDG_STATE_HOME/desktop-shell"
printf '1\n' >"$XDG_STATE_HOME/desktop-shell/dnd"
printf '1\n' >"$XDG_STATE_HOME/desktop-shell/focus"

provider_config="$test_root/provider-config.json"
jq \
  '.bar.networkControls = [{
    id: "demo",
    label: "Demo",
    icon: "",
    statusCommand: ["printf", "%s\\n", "{\"text\":\"Demo\",\"active\":true}"],
    toggleCommand: ["true"]
  }] |
  .display.startupLayout = [{
    output: "eDP-1",
    mode: "preferred",
    position: "0x0",
    scale: 2,
    bitdepth: null
  }] |
  .launcher.profiles = {"test-profile": {
    label: "Test profile",
    icon: "applications-other",
    applications: [{id: "org.example.Demo.desktop", workspace: 2}]
  }} |
  .launcher.autoStartProfile = "test-profile"' \
  "$default_config" >"$provider_config"
export DESKTOP_SHELL_CONFIG="$provider_config"

# shellcheck source=../src/backend/lib/common.sh
source "$source_root/src/backend/lib/common.sh"
# shellcheck source=../src/backend/lib/network.sh
source "$source_root/src/backend/lib/network.sh"
# shellcheck source=../src/backend/lib/brightness.sh
source "$source_root/src/backend/lib/brightness.sh"
# shellcheck source=../src/backend/lib/bluetooth.sh
source "$source_root/src/backend/lib/bluetooth.sh"
# shellcheck source=../src/backend/lib/display.sh
source "$source_root/src/backend/lib/display.sh"

test "$(cat "$XDG_STATE_HOME/desktop-shell/preferences/dnd")" = 1
test "$(cat "$XDG_STATE_HOME/desktop-shell/preferences/focus")" = 1
write_preference focus 0
test "$(cat "$XDG_STATE_HOME/desktop-shell/preferences/focus")" = 0

network_control_command demo status | jq -e '.text == "Demo" and .active == true' >/dev/null
network_control_command demo toggle

brightness_capabilities_json | jq -e '.supported == false and .backend == ""' >/dev/null

backlight="$DESKTOP_SHELL_SYS_ROOT/class/backlight/test-backlight"
mkdir -p "$backlight"
printf '50\n' >"$backlight/brightness"
printf '100\n' >"$backlight/max_brightness"
brightness_capabilities_json | jq -e '.supported == true and .backend == "backlight" and .writable == true' >/dev/null
test "$(brightness_get)" = 50

test_bin="$test_root/bin"
hyprctl_args="$test_root/hyprctl-args"
hyprctl_eval="$test_root/hyprctl-eval"
monitors_json="$test_root/monitors.json"
mkdir -p "$test_bin"
printf '#!%s\nexit 1\n' "$(command -v bash)" >"$test_bin/quickshell"
printf '#!%s\nprintf \"%%s\\n\" \"$@\" >\"$DESKTOP_SHELL_TEST_HYPRCTL_ARGS\"\n' \
  "$(command -v bash)" >"$test_bin/hyprctl"
chmod +x "$test_bin/quickshell" "$test_bin/hyprctl"
export DESKTOP_SHELL_TEST_HYPRCTL_ARGS="$hyprctl_args"
export DESKTOP_SHELL_TEST_HYPRCTL_EVAL="$hyprctl_eval"
export DESKTOP_SHELL_TEST_MONITORS_JSON="$monitors_json"

fast_ipc_args="$test_root/fast-ipc-args"
invalid_config="$test_root/invalid-config.json"
printf '{\n' >"$invalid_config"
printf '#!%s\nprintf "%%s\\n" "$@" >"$DESKTOP_SHELL_TEST_FAST_IPC_ARGS"\n' \
  "$(command -v bash)" >"$test_bin/quickshell"
chmod +x "$test_bin/quickshell"
DESKTOP_SHELL_TEST_FAST_IPC_ARGS="$fast_ipc_args" \
  DESKTOP_SHELL_CONFIG="$invalid_config" \
  DESKTOP_SHELL_DEFAULT_CONFIG="$invalid_config" \
  PATH="$test_bin:$PATH" \
  bash "$source_root/src/backend/desktop-shell.sh" launcher open
mapfile -t captured_fast_ipc_args <"$fast_ipc_args"
test "${captured_fast_ipc_args[0]}" = ipc
test "${captured_fast_ipc_args[3]}" = call
test "${captured_fast_ipc_args[4]}" = launcher
test "${captured_fast_ipc_args[5]}" = open

profile_ipc_args="$test_root/profile-ipc-args"
printf '#!%s\nif [ "${6:-}" = profileReady ]; then printf "true\\n"; else printf "%%s\\n" "$@" >"$DESKTOP_SHELL_TEST_PROFILE_IPC_ARGS"; fi\n' \
  "$(command -v bash)" >"$test_bin/quickshell"
chmod +x "$test_bin/quickshell"
DESKTOP_SHELL_TEST_PROFILE_IPC_ARGS="$profile_ipc_args" \
  PATH="$test_bin:$PATH" \
  bash "$source_root/src/backend/desktop-shell.sh" profile apply test-profile
mapfile -t captured_profile_ipc_args <"$profile_ipc_args"
test "${captured_profile_ipc_args[0]}" = ipc
test "${captured_profile_ipc_args[3]}" = call
test "${captured_profile_ipc_args[4]}" = launcher
test "${captured_profile_ipc_args[5]}" = applyProfile
test "${captured_profile_ipc_args[6]}" = test-profile
bash "$source_root/src/backend/desktop-shell.sh" profile list-json |
  jq -e '.["test-profile"] == {
    "label":"Test profile",
    "icon":"applications-other",
    "applications":[{"id":"org.example.Demo.desktop","workspace":2}]
  }' >/dev/null
if PATH="$test_bin:$PATH" \
  bash "$source_root/src/backend/desktop-shell.sh" profile apply missing >/dev/null 2>&1; then
  exit 1
fi

PATH="$test_bin:$PATH" \
  bash "$source_root/src/backend/desktop-shell.sh" launcher launch-in-workspace org.example.Demo.desktop 2
mapfile -t captured_profile_launch_args <"$hyprctl_args"
test "${captured_profile_launch_args[0]}" = eval
test "${captured_profile_launch_args[1]}" = \
  'hl.exec_cmd("uwsm app -- org.example.Demo.desktop", { workspace = "2 silent", focus_on_activate = false })'
if PATH="$test_bin:$PATH" \
  bash "$source_root/src/backend/desktop-shell.sh" launcher launch-in-workspace 'invalid;entry.desktop' 2 \
  >/dev/null 2>&1; then
  exit 1
fi
if PATH="$test_bin:$PATH" \
  bash "$source_root/src/backend/desktop-shell.sh" launcher launch-in-workspace org.example.Demo.desktop 0 \
  >/dev/null 2>&1; then
  exit 1
fi

PATH="$test_bin:$PATH" \
  bash "$source_root/src/backend/desktop-shell.sh" launcher move-to-workspace 0xabc123 2
mapfile -t captured_profile_move_args <"$hyprctl_args"
test "${captured_profile_move_args[0]}" = dispatch
test "${captured_profile_move_args[1]}" = \
  'hl.dsp.window.move({ workspace = 2, follow = false, window = "address:0xabc123" })'
if PATH="$test_bin:$PATH" \
  bash "$source_root/src/backend/desktop-shell.sh" launcher move-to-workspace 'bad;address' 2 \
  >/dev/null 2>&1; then
  exit 1
fi

printf '#!%s\nprintf "true\\n"\n' "$(command -v bash)" >"$test_bin/quickshell"
chmod +x "$test_bin/quickshell"
DESKTOP_SHELL_CONFIG="$invalid_config" \
  DESKTOP_SHELL_DEFAULT_CONFIG="$invalid_config" \
  PATH="$test_bin:$PATH" \
  bash "$source_root/src/backend/desktop-shell.sh" wait-ready

fast_brightness="$({
  DESKTOP_SHELL_CONFIG="$invalid_config" \
    DESKTOP_SHELL_DEFAULT_CONFIG="$invalid_config" \
    bash "$source_root/src/backend/desktop-shell.sh" brightness get
})"
test "$fast_brightness" = 50

printf '#!%s\nexit 1\n' "$(command -v bash)" >"$test_bin/quickshell"
chmod +x "$test_bin/quickshell"

bluetoothctl_args="$test_root/bluetoothctl-args"
printf '#!%s\nprintf \"%%s\\n\" \"$*\" >>\"$DESKTOP_SHELL_TEST_BLUETOOTHCTL_ARGS\"\n' \
  "$(command -v bash)" >"$test_bin/bluetoothctl"
chmod +x "$test_bin/bluetoothctl"
export DESKTOP_SHELL_TEST_BLUETOOTHCTL_ARGS="$bluetoothctl_args"
PATH="$test_bin:$PATH" bluetooth_private_mode
mapfile -t captured_bluetoothctl_args <"$bluetoothctl_args"
test "${captured_bluetoothctl_args[0]}" = "discoverable off"
test "${captured_bluetoothctl_args[1]}" = "pairable off"

: >"$bluetoothctl_args"
test "$(printf 'close\n' | PATH="$test_bin:$PATH" bluetooth_pairing_session)" = ready
mapfile -t captured_bluetoothctl_args <"$bluetoothctl_args"
test "${captured_bluetoothctl_args[0]}" = "pairable on"
test "${captured_bluetoothctl_args[1]}" = "discoverable on"
test "${captured_bluetoothctl_args[2]}" = "discoverable off"
test "${captured_bluetoothctl_args[3]}" = "pairable off"

PATH="$test_bin:$PATH" bash "$source_root/src/backend/desktop-shell.sh" direction l
mapfile -t captured_hyprctl_args <"$hyprctl_args"
test "${captured_hyprctl_args[0]}" = dispatch
test "${captured_hyprctl_args[1]}" = 'hl.dsp.focus({ direction = "l" })'

printf '%s\n' \
  "#!$(command -v bash)" \
  'printf "%s\n" "$@" >"$DESKTOP_SHELL_TEST_HYPRCTL_ARGS"' \
  'case "${1:-}" in' \
  '  monitors) cat "$DESKTOP_SHELL_TEST_MONITORS_JSON" ;;' \
  '  eval) printf "%s\n" "${2:-}" >"$DESKTOP_SHELL_TEST_HYPRCTL_EVAL"; printf "ok\n" ;;' \
  '  reload) printf "reload\n" >"$DESKTOP_SHELL_TEST_HYPRCTL_EVAL" ;;' \
  'esac' >"$test_bin/hyprctl"
chmod +x "$test_bin/hyprctl"

jq -n '
  [
    {
      id: 0,
      name: "eDP-1",
      description: "Laptop Panel",
      make: "Panel Corp",
      model: "Internal",
      serial: "",
      width: 2880,
      height: 1800,
      refreshRate: 120,
      x: 0,
      y: 0,
      scale: 2,
      focused: true,
      disabled: false,
      mirrorOf: "none",
      availableModes: ["2880x1800@120.00Hz", "1920x1080@60.00Hz"]
    },
    {
      id: 1,
      name: "DP-5",
      description: "Acer X34 ABC",
      make: "Acer",
      model: "X34",
      serial: "ABC",
      width: 3440,
      height: 1440,
      refreshRate: 240,
      x: 1440,
      y: 0,
      scale: 1.25,
      focused: false,
      disabled: false,
      mirrorOf: "none",
      availableModes: ["3440x1440@240.00Hz", "1920x1080@144.00Hz", "1920x1080@60.00Hz"]
    }
  ]
' >"$monitors_json"

display_snapshot="$(PATH="$test_bin:$PATH" display_snapshot_json)"
jq -e '
  .activeCount == 2 and
  .internalCount == 1 and
  .externalCount == 1 and
  .outputs[0].identity == "description:Laptop Panel" and
  .outputs[1].identity == "edid:Acer|X34|ABC" and
  .outputs[1].mode == "3440x1440@240.00"
' <<<"$display_snapshot" >/dev/null

PATH="$test_bin:$PATH" display_status_json | jq -e '
  .profileAvailable == false and .pending == null and
  .startupLayout == [{output: "eDP-1", mode: "preferred", position: "0x0", scale: 2, bitdepth: null}] and
  (.outputs | length) == 2
' >/dev/null

duplicate_layout="$(
  display_layout_from_request "$display_snapshot" '{"preset":"duplicate","primary":"eDP-1"}'
)"
jq -e '
  .primary == "eDP-1" and
  ([.outputs[] | select(.enabled and (.mode | startswith("1920x1080@")))] | length) == 2 and
  ([.outputs[] | select(.name == "DP-5")][0].mirror == "eDP-1")
' <<<"$duplicate_layout" >/dev/null

internal_layout="$(
  display_layout_from_request "$display_snapshot" '{"preset":"internal","primary":"DP-5"}'
)"
jq -e '
  .primary == "eDP-1" and
  ([.outputs[] | select(.name == "eDP-1")][0].enabled == true) and
  ([.outputs[] | select(.name == "DP-5")][0].enabled == false)
' <<<"$internal_layout" >/dev/null

if display_layout_from_request "$display_snapshot" \
  '{"preset":"custom","primary":"eDP-1","changes":{"eDP-1":{"scale":9}}}' >/dev/null 2>&1; then
  exit 1
fi

arranged_layout="$(
  display_layout_from_request "$display_snapshot" \
    '{"preset":"custom","primary":"DP-5","changes":{"eDP-1":{"position":"1720x0"},"DP-5":{"position":"0x180"}}}'
)"
jq -e '
  .primary == "DP-5" and
  ([.outputs[] | select(.name == "eDP-1")][0].position == "1720x0") and
  ([.outputs[] | select(.name == "DP-5")][0].position == "0x180")
' <<<"$arranged_layout" >/dev/null

if display_layout_from_request "$display_snapshot" \
  '{"preset":"custom","changes":{"eDP-1":{"position":"somewhere"}}}' >/dev/null 2>&1; then
  exit 1
fi

systemd_run_args="$test_root/systemd-run-args"
printf '#!%s\nprintf "%%s\\n" "$@" >"$DESKTOP_SHELL_TEST_SYSTEMD_RUN_ARGS"\n' \
  "$(command -v bash)" >"$test_bin/systemd-run"
printf '#!%s\nexit 0\n' "$(command -v bash)" >"$test_bin/systemctl"
chmod +x "$test_bin/systemd-run" "$test_bin/systemctl"
export DESKTOP_SHELL_TEST_SYSTEMD_RUN_ARGS="$systemd_run_args"

apply_result="$(
  PATH="$test_bin:$PATH" display_apply_request '{"preset":"duplicate","primary":"eDP-1"}'
)"
display_token="$(jq -r '.token' <<<"$apply_result")"
test -n "$display_token"
test -r "$display_pending_file"
grep -F 'hl.monitor({ output = "DP-5"' "$hyprctl_eval" >/dev/null
grep -F 'mirror = "eDP-1"' "$hyprctl_eval" >/dev/null
grep -F -- '--on-active=20s' "$systemd_run_args" >/dev/null

PATH="$test_bin:$PATH" display_keep "$display_token"
test ! -e "$display_pending_file"
jq -e '.profiles | length == 1' "$display_profiles_file" >/dev/null

jq 'map(if .name == "DP-5" then .name = "DP-6" else . end)' "$monitors_json" >"$monitors_json.next"
mv "$monitors_json.next" "$monitors_json"
PATH="$test_bin:$PATH" display_restore_profile
grep -F 'hl.monitor({ output = "DP-6"' "$hyprctl_eval" >/dev/null
grep -F 'mirror = "eDP-1"' "$hyprctl_eval" >/dev/null

apply_result="$(
  PATH="$test_bin:$PATH" display_apply_request '{"preset":"external","primary":"DP-6"}'
)"
display_token="$(jq -r '.token' <<<"$apply_result")"
PATH="$test_bin:$PATH" display_rollback "$display_token"
test ! -e "$display_pending_file"

apply_result="$(
  PATH="$test_bin:$PATH" display_apply_request '{"preset":"external","primary":"DP-6"}'
)"
display_token="$(jq -r '.token' <<<"$apply_result")"
jq '.deadline = 0' "$display_pending_file" >"$display_pending_file.next"
mv "$display_pending_file.next" "$display_pending_file"
PATH="$test_bin:$PATH" display_restore_profile
test ! -e "$display_pending_file"

jq '.profiles += [{"topology":"another-display-set","primaryIdentity":"","outputs":[]}]' \
  "$display_profiles_file" >"$display_profiles_file.next"
mv "$display_profiles_file.next" "$display_profiles_file"
PATH="$test_bin:$PATH" display_reset
jq -e '.profiles == [{"topology":"another-display-set","primaryIdentity":"","outputs":[]}]' \
  "$display_profiles_file" >/dev/null
grep -Fx reload "$hyprctl_eval" >/dev/null
