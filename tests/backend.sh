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

network_control_command demo status | jq -e '.text == "Demo" and .active == true' >/dev/null
network_control_command demo toggle

brightness_capabilities_json | jq -e '.supported == false and .backend == ""' >/dev/null

backlight="$DESKTOP_SHELL_SYS_ROOT/class/backlight/test-backlight"
mkdir -p "$backlight"
printf '50\n' >"$backlight/brightness"
printf '100\n' >"$backlight/max_brightness"
brightness_capabilities_json | jq -e '.supported == true and .backend == "backlight"' >/dev/null
test "$(brightness_get)" = 50
