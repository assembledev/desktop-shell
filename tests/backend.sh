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

provider_config="$test_root/provider-config.json"
jq \
  '.bar.networkControls = [{
    id: "demo",
    label: "Demo",
    icon: "",
    statusCommand: ["printf", "%s\\n", "{\"text\":\"Demo\",\"active\":true}"],
    toggleCommand: ["true"]
  }]' \
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

network_control_command demo status | jq -e '.text == "Demo" and .active == true' >/dev/null
network_control_command demo toggle

brightness_capabilities_json | jq -e '.supported == false and .backend == ""' >/dev/null

backlight="$DESKTOP_SHELL_SYS_ROOT/class/backlight/test-backlight"
mkdir -p "$backlight"
printf '50\n' >"$backlight/brightness"
printf '100\n' >"$backlight/max_brightness"
brightness_capabilities_json | jq -e '.supported == true and .backend == "backlight"' >/dev/null
test "$(brightness_get)" = 50

test_bin="$test_root/bin"
hyprctl_args="$test_root/hyprctl-args"
mkdir -p "$test_bin"
printf '#!%s\nexit 1\n' "$(command -v bash)" >"$test_bin/quickshell"
printf '#!%s\nprintf \"%%s\\n\" \"$@\" >\"$DESKTOP_SHELL_TEST_HYPRCTL_ARGS\"\n' \
  "$(command -v bash)" >"$test_bin/hyprctl"
chmod +x "$test_bin/quickshell" "$test_bin/hyprctl"
export DESKTOP_SHELL_TEST_HYPRCTL_ARGS="$hyprctl_args"

bluetoothctl_args="$test_root/bluetoothctl-args"
printf '#!%s\nprintf \"%%s\\n\" \"$@\" >\"$DESKTOP_SHELL_TEST_BLUETOOTHCTL_ARGS\"\nexit 1\n' \
  "$(command -v bash)" >"$test_bin/bluetoothctl"
chmod +x "$test_bin/bluetoothctl"
export DESKTOP_SHELL_TEST_BLUETOOTHCTL_ARGS="$bluetoothctl_args"
PATH="$test_bin:$PATH" bluetooth_private_mode
mapfile -t captured_bluetoothctl_args <"$bluetoothctl_args"
test "${captured_bluetoothctl_args[0]}" = --timeout
test "${captured_bluetoothctl_args[1]}" = 2
test "${captured_bluetoothctl_args[2]}" = discoverable
test "${captured_bluetoothctl_args[3]}" = off

PATH="$test_bin:$PATH" bash "$source_root/src/backend/desktop-shell.sh" direction l
mapfile -t captured_hyprctl_args <"$hyprctl_args"
test "${captured_hyprctl_args[0]}" = dispatch
test "${captured_hyprctl_args[1]}" = 'hl.dsp.focus({ direction = "l" })'
