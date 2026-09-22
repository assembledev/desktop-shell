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
mkdir -p "$XDG_STATE_HOME/desktop-shell/preferences"
printf '1\n' >"$XDG_STATE_HOME/desktop-shell/preferences/dnd"
printf '1\n' >"$XDG_STATE_HOME/desktop-shell/preferences/focus"

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

# Provider commands are argv, including empty and multiline arguments.
argv_config="$test_root/argv-config.json"
jq '.bar.networkControls[0].statusCommand = ["printf", "<%s>", "first\nsecond", "", "last"]' \
  "$provider_config" >"$argv_config"
test "$(desktop_shell_config="$argv_config" network_control_command demo status)" = $'<first\nsecond><><last>'
# Invalid commands must fail before invoking even a valid prefix.
jq --arg path "$test_root/unexpected-command" \
  '.bar.networkControls[0].statusCommand = ["touch", $path, null]' \
  "$provider_config" >"$argv_config"
if desktop_shell_config="$argv_config" network_control_command demo status 2>/dev/null; then
  printf 'invalid provider argv must fail\n' >&2
  exit 1
fi
test ! -e "$test_root/unexpected-command"
network_control_command demo toggle

brightness_capabilities_json | jq -e '.supported == false and .backend == ""' >/dev/null

backlight="$DESKTOP_SHELL_SYS_ROOT/class/backlight/test-backlight"
mkdir -p "$backlight"
printf '50\n' >"$backlight/brightness"
printf '100\n' >"$backlight/max_brightness"
brightness_capabilities_json | jq -e '.supported == true and .backend == "backlight" and .writable == true' >/dev/null
test "$(brightness_get)" = 50

# DDC publishes its initial read before the UI starts watching the cache file.
(
  brightness_device_dir() { return 1; }
  brightness_ddc_target_bus() { printf '999\n'; }
  brightness_target_values() { printf 'ddc\t999\t40\t100\n'; }
  brightness_capabilities_json | jq -e --arg path "$brightness_value_file" \
    '.backend == "ddc" and .valuePath == $path' >/dev/null
  test "$(brightness_get)" = 40
  test "$(cat "$brightness_value_file")" = 40
)

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

# Every regular backend command must parse the shared config only once.
export DESKTOP_SHELL_TEST_REAL_JQ="$(command -v jq)"
export DESKTOP_SHELL_TEST_JQ_CALLS="$test_root/jq-calls"
printf '%s\n' \
  "#!$(command -v bash)" \
  'printf "call\n" >>"$DESKTOP_SHELL_TEST_JQ_CALLS"' \
  'exec "$DESKTOP_SHELL_TEST_REAL_JQ" "$@"' >"$test_bin/jq"
chmod +x "$test_bin/jq"
PATH="$test_bin:$PATH" bash "$source_root/src/backend/desktop-shell.sh" help >/dev/null
jq_calls="$(wc -l <"$DESKTOP_SHELL_TEST_JQ_CALLS")"
if [ "$jq_calls" -ne 1 ]; then
  printf 'shared backend setup invoked jq %s times; expected one\n' "$jq_calls" >&2
  exit 1
fi
rm "$test_bin/jq"

# Config strings remain literal, including whitespace and shell syntax.
config_fixture="$test_root/config-fixture.json"
export DESKTOP_SHELL_TEST_LITERAL=$'quotes " \' `false` $(false) \\ tabs\tand\nnewlines\n'
jq --arg literal "$DESKTOP_SHELL_TEST_LITERAL" \
  '.output = $literal | .browserTabs.displayName = $literal |
   .integrations.recordingStateFile = "capture/state" | .bar.showVram = false' \
  "$provider_config" >"$config_fixture"
DESKTOP_SHELL_CONFIG="$config_fixture" bash -eu -s -- "$source_root" <<'EOF'
source "$1/src/backend/lib/common.sh"
test "$DESKTOP_SHELL_OUTPUT" = "$DESKTOP_SHELL_TEST_LITERAL"
test "$DESKTOP_SHELL_BROWSER_NAME" = "$DESKTOP_SHELL_TEST_LITERAL"
test "$DESKTOP_SHELL_RECORDING_STATE" = "$XDG_RUNTIME_DIR/capture/state"
test "$DESKTOP_SHELL_BAR_SHOW_VRAM" = 0
bash -eu -c 'test "$DESKTOP_SHELL_OUTPUT" = "$DESKTOP_SHELL_TEST_LITERAL"'
EOF

printf '{}\n' >"$config_fixture"
DESKTOP_SHELL_CONFIG="$config_fixture" bash -eu -s -- "$source_root" <<'EOF'
source "$1/src/backend/lib/common.sh"
test "$DESKTOP_SHELL_WORKSPACES_JSON" = "[]"
test "$DESKTOP_SHELL_KEYBOARD_LABELS_JSON" = '["EN"]'
test "$DESKTOP_SHELL_THEME_JSON" = "{}"
test "$DESKTOP_SHELL_BAR_COMPACT" = 0
test "$DESKTOP_SHELL_BAR_SHOW_VRAM" = 1
test "$DESKTOP_SHELL_OUTPUT" = ""
test "$wallpaper_dir" = "$HOME/Wallpapers"
test "$default_wallpaper" = "$HOME/Wallpapers/wallpaper.jpg"
EOF

for invalid_json in '{' '[]' 'null' '' '{"output":"a\u0000b"}'; do
  printf '%s' "$invalid_json" >"$config_fixture"
  if DESKTOP_SHELL_CONFIG="$config_fixture" \
    bash "$source_root/src/backend/desktop-shell.sh" help >/dev/null 2>&1; then
    printf 'backend must reject invalid configuration\n' >&2
    exit 1
  fi
done

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

DESKTOP_SHELL_TEST_FAST_IPC_ARGS="$fast_ipc_args" \
  DESKTOP_SHELL_CONFIG="$invalid_config" \
  DESKTOP_SHELL_DEFAULT_CONFIG="$invalid_config" \
  PATH="$test_bin:$PATH" \
  bash "$source_root/src/backend/desktop-shell.sh" clipboard refresh
mapfile -t captured_fast_ipc_args <"$fast_ipc_args"
test "${captured_fast_ipc_args[0]}" = ipc
test "${captured_fast_ipc_args[3]}" = call
test "${captured_fast_ipc_args[4]}" = clipboardHistory
test "${captured_fast_ipc_args[5]}" = refresh

clipboard_list="$test_root/clipboard-list"
printf '%s\n' \
  $'101\tText with <markup> and a tab\tinside' \
  $'102\t[[ binary data 12 KiB png 640x480 ]]' \
  'record-without-a-tab' >"$clipboard_list"
printf '%s\n' \
  "#!$(command -v bash)" \
  'test "${1:-}" = list' \
  'cat "$DESKTOP_SHELL_TEST_CLIPBOARD_LIST"' >"$test_bin/cliphist"
chmod +x "$test_bin/cliphist"
clipboard_json="$(
  DESKTOP_SHELL_TEST_CLIPBOARD_LIST="$clipboard_list" \
    DESKTOP_SHELL_CONFIG="$invalid_config" \
    DESKTOP_SHELL_DEFAULT_CONFIG="$invalid_config" \
    PATH="$test_bin:$PATH" \
    bash "$source_root/src/backend/desktop-shell.sh" clipboard list-json
)"
jq -e \
  --arg text_record "$(printf '%s' $'101\tText with <markup> and a tab\tinside' | base64 -w0)" \
  --arg image_record "$(printf '%s' $'102\t[[ binary data 12 KiB png 640x480 ]]' | base64 -w0)" \
  --arg fallback_record "$(printf '%s' 'record-without-a-tab' | base64 -w0)" \
  '
    length == 3 and
    .[0] == {
      entryId: "101",
      label: "Text with <markup> and a tab\tinside",
      record: $text_record,
      preview: "",
      kind: "text",
      dimensions: "",
      size: "",
      createdAt: 0,
      image: false
    } and
    .[1] == {
      entryId: "102",
      label: "[[ binary data 12 KiB png 640x480 ]]",
      record: $image_record,
      preview: "",
      kind: "png",
      dimensions: "640x480",
      size: "12 KiB",
      createdAt: 0,
      image: true
    } and
    .[2] == {
      entryId: "record-without-a-tab",
      label: "record-without-a-tab",
      record: $fallback_record,
      preview: "",
      kind: "text",
      dimensions: "",
      size: "",
      createdAt: 0,
      image: false
    }
  ' <<<"$clipboard_json" >/dev/null

# Capture ages are recorded only for a successful new head, survive reads, and
# disappear with their records. Old or reused IDs must never acquire false ages.
# shellcheck source=../src/backend/lib/clipboard.sh
source "$source_root/src/backend/lib/clipboard.sh"
export DESKTOP_SHELL_TEST_CLIPBOARD_LIST="$clipboard_list"
export DESKTOP_SHELL_TEST_CLIPBOARD_NEXT="$test_root/clipboard-next"
printf '#!%s\n' "$(command -v bash)" >"$test_bin/cliphist"
cat >>"$test_bin/cliphist" <<'CLIPHIST'
case "$1" in
  list) cat "$DESKTOP_SHELL_TEST_CLIPBOARD_LIST" ;;
  store)
    cat >/dev/null
    [ "${DESKTOP_SHELL_TEST_STORE_FAIL:-0}" = 0 ] || exit 1
    cp "$DESKTOP_SHELL_TEST_CLIPBOARD_NEXT" "$DESKTOP_SHELL_TEST_CLIPBOARD_LIST"
    ;;
  delete)
    IFS=$'\t' read -r id rest
    awk -F '\t' -v id="$id" '$1 != id' "$DESKTOP_SHELL_TEST_CLIPBOARD_LIST" >"$DESKTOP_SHELL_TEST_CLIPBOARD_NEXT"
    cp "$DESKTOP_SHELL_TEST_CLIPBOARD_NEXT" "$DESKTOP_SHELL_TEST_CLIPBOARD_LIST"
    ;;
  wipe) : >"$DESKTOP_SHELL_TEST_CLIPBOARD_LIST" ;;
esac
CLIPHIST
chmod +x "$test_bin/cliphist"
printf '%s\n' $'103\thttps://example.com' >"$DESKTOP_SHELL_TEST_CLIPBOARD_NEXT"
cat "$clipboard_list" >>"$DESKTOP_SHELL_TEST_CLIPBOARD_NEXT"
printf sample | PATH="$test_bin:$PATH" \
  DESKTOP_SHELL_CONFIG="$invalid_config" \
  bash "$source_root/src/backend/desktop-shell.sh" clipboard store
aged_json="$(PATH="$test_bin:$PATH" clipboard_list_json)"
jq -e '.[0].createdAt > 0 and (.[1:] | all(.createdAt == 0))' <<<"$aged_json" >/dev/null
ages_file="$(clipboard_age_file)"
test "$(stat -c %a "$ages_file")" = 600
saved_ages="$(cat "$ages_file")"
# An ignored capture has the same head and must preserve its age.
printf ignored | PATH="$test_bin:$PATH" clipboard_store
test "$(cat "$ages_file")" = "$saved_ages"
if printf failure | PATH="$test_bin:$PATH" DESKTOP_SHELL_TEST_STORE_FAIL=1 \
  bash "$source_root/src/backend/desktop-shell.sh" clipboard store; then
  printf 'failed store must propagate failure\n' >&2
  exit 1
fi
test "$(cat "$ages_file")" = "$saved_ages"
# Same ID with different content is not the timestamped record.
printf '%s\n' $'103\treused ID' >"$clipboard_list"
PATH="$test_bin:$PATH" clipboard_list_json | jq -e '.[0].createdAt == 0' >/dev/null
printf '%s\n' $'104\tnew capture' >"$DESKTOP_SHELL_TEST_CLIPBOARD_NEXT"
printf sample | PATH="$test_bin:$PATH" clipboard_store
jq -e 'keys == ["104"]' "$ages_file" >/dev/null
# Delete clears metadata; a successful wipe clears the file entirely.
delete_record="$(printf '%s' $'104\tnew capture' | base64 -w0)"
PATH="$test_bin:$PATH" clipboard_delete "$delete_record" 104 text
jq -e 'length == 0' "$ages_file" >/dev/null
printf sample | PATH="$test_bin:$PATH" clipboard_store
PATH="$test_bin:$PATH" clipboard_wipe
test ! -e "$ages_file"

# Copying must not load shell configuration, and must wait for the writer.
printf '%s\n' \
  "#!$(command -v bash)" \
  'test "${1:-}" = decode || exit 1' \
  'cat' >"$test_bin/cliphist"
printf '%s\n' \
  "#!$(command -v bash)" \
  'cat >"$DESKTOP_SHELL_TEST_COPY_OUTPUT"' \
  'sleep 0.05' \
  'touch "$DESKTOP_SHELL_TEST_COPY_DONE"' \
  'exit "${DESKTOP_SHELL_TEST_COPY_STATUS:-0}"' >"$test_bin/wl-copy"
chmod +x "$test_bin/cliphist" "$test_bin/wl-copy"
export DESKTOP_SHELL_TEST_COPY_OUTPUT="$test_root/copied"
export DESKTOP_SHELL_TEST_COPY_DONE="$test_root/copy-done"
copy_record="$(printf '%s' $'101\tsample' | base64 -w0)"
DESKTOP_SHELL_CONFIG="$invalid_config" \
  DESKTOP_SHELL_DEFAULT_CONFIG="$invalid_config" \
  PATH="$test_bin:$PATH" \
  bash "$source_root/src/backend/desktop-shell.sh" clipboard copy "$copy_record"
test "$(cat "$DESKTOP_SHELL_TEST_COPY_OUTPUT")" = $'101\tsample'
test -f "$DESKTOP_SHELL_TEST_COPY_DONE"
if DESKTOP_SHELL_TEST_COPY_STATUS=1 PATH="$test_bin:$PATH" \
  bash "$source_root/src/backend/desktop-shell.sh" clipboard copy "$copy_record"; then
  printf 'clipboard copy must propagate writer failure\n' >&2
  exit 1
fi

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

printf '#!%s\nprintf "%%s\\n" "$@" >"$DESKTOP_SHELL_TEST_HYPRCTL_ARGS"\n' \
  "$(command -v bash)" >"$test_bin/hyprctl"
chmod +x "$test_bin/hyprctl"

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

# Adapter polling parses one response, preserving aliases and absent adapters.
bluetoothctl() {
  test "$1" = show || return 1
  printf '%s\n' 'Controller AA:BB:CC:DD:EE:FF Test [default]' \
    $'\tPowered: yes' $'\tDiscoverable: no' $'\tPairable: yes' \
    $'\tDiscovering: no' $'\tAlias: Desk: "Radio"' $'\tAlias: Ignore duplicate'
}
bluetooth_status_json | jq -e '. == {
  available: true, enabled: true, discoverable: false, pairable: true,
  discovering: false, controller: "AA:BB:CC:DD:EE:FF", alias: "Desk: \"Radio\""
}' >/dev/null
bluetoothctl() {
  printf 'No default controller available\n'
  return 1
}
bluetooth_status_json | jq -e '. == {
  available: false, enabled: false, discoverable: false, pairable: false,
  discovering: false, controller: "", alias: ""
}' >/dev/null
unset -f bluetoothctl

# Parse each complete device response once, retaining aliases, missing values,
# decimal/hex measurements, ordering, and discovery-list deduplication.
bluetoothctl() {
  case "$1 ${2:-}" in
    devices*)
      printf '%s\n' 'Device AA:BB:CC:DD:EE:01 One' 'Device AA:BB:CC:DD:EE:02 Two' 'Device AA:BB:CC:DD:EE:03 Three' 'Device AA:BB:CC:DD:EE:04 Gone'
      ;;
    'info AA:BB:CC:DD:EE:01')
      printf '%s\n' 'Device AA:BB:CC:DD:EE:01' $'\tAlias: Headset: "Office"' $'\tName: Ignored' $'\tIcon: audio-headset' $'\tPaired: yes' $'\tTrusted: yes' $'\tConnected: yes' $'\tRSSI: 0xffffffc4 (-60)' $'\tBattery Percentage: 0x4b (75)'
      ;;
    'info AA:BB:CC:DD:EE:02')
      printf '%s\n' $'\tName: Keyboard' $'\tPaired: yes' $'\tRSSI: -110'
      ;;
    'info AA:BB:CC:DD:EE:03')
      printf '%s\n' $'\tConnected: no' $'\tRSSI: -30' $'\tBattery Percentage: 90'
      ;;
    *) return 0 ;;
  esac
}
bluetooth_devices_json | jq -e '
  length == 3 and
  .[0] == {address: "AA:BB:CC:DD:EE:01", name: "Headset: \"Office\"", icon: "audio-headset", paired: true, trusted: true, connected: true, rssi: -60, signal: 80, battery: 75} and
  .[1].name == "Keyboard" and .[1].signal == 0 and .[1].battery == null and
  .[2].name == "AA:BB:CC:DD:EE:03" and .[2].signal == 100 and .[2].battery == 90
' >/dev/null
unset -f bluetoothctl

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
      transform: 1,
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
  .outputs[1].mode == "3440x1440@240.00" and .outputs[1].transform == 1
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
    '{"preset":"custom","primary":"DP-5","changes":{"eDP-1":{"position":"2752x0"},"DP-5":{"position":"0x180"}}}'
)"
jq -e '
  .primary == "DP-5" and
  ([.outputs[] | select(.name == "eDP-1")][0].position == "2752x0") and
  ([.outputs[] | select(.name == "DP-5")][0].position == "0x180")
' <<<"$arranged_layout" >/dev/null

if display_layout_from_request "$display_snapshot" \
  '{"preset":"custom","changes":{"eDP-1":{"position":"somewhere"}}}' >/dev/null 2>&1; then
  exit 1
fi

# Rotated external output is 1152 x 2752 logical pixels. Each alignment must
# reach the backend as a distinct exact position while keeping a shared edge.
for aligned_y in 0 926 1852; do
  request="$(jq -nc --arg position "1152x$aligned_y" '{preset:"custom", changes:{"eDP-1":{position:$position},"DP-5":{position:"0x0"}}}')"
  display_layout_from_request "$display_snapshot" "$request" |
    jq -e --arg position "1152x$aligned_y" '.outputs[0].position == $position and .outputs[1].transform == 1' >/dev/null
done
if display_layout_from_request "$display_snapshot" \
  '{"preset":"custom","changes":{"eDP-1":{"position":"0x0"},"DP-5":{"position":"0x0"}}}' >/dev/null 2>&1; then
  printf 'overlapping extended displays must be rejected\n' >&2
  exit 1
fi
display_layout_from_request "$display_snapshot" \
  '{"preset":"custom","changes":{"eDP-1":{"position":"-1440x0"},"DP-5":{"position":"0x0"}}}' |
  jq -e '.outputs[0].position == "-1440x0"' >/dev/null

# Profiles from before rotation was recorded inherit the current output transform.
legacy_profile="$(display_profile_from_layout "$arranged_layout" | jq 'del(.outputs[].transform)')"
display_layout_from_profile "$display_snapshot" "$legacy_profile" |
  jq -e '.outputs[1].transform == 1' >/dev/null

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
grep -F 'transform = 1' "$hyprctl_eval" >/dev/null
grep -F -- '--on-active=20s' "$systemd_run_args" >/dev/null

PATH="$test_bin:$PATH" display_keep "$display_token"
test ! -e "$display_pending_file"
jq -e '(.profiles | length == 1) and .profiles[0].outputs[1].transform == 1' "$display_profiles_file" >/dev/null

jq 'map(if .name == "DP-5" then .name = "DP-6" else . end)' "$monitors_json" >"$monitors_json.next"
mv "$monitors_json.next" "$monitors_json"
PATH="$test_bin:$PATH" display_restore_profile
grep -F 'hl.monitor({ output = "DP-6"' "$hyprctl_eval" >/dev/null
grep -F 'mirror = "eDP-1"' "$hyprctl_eval" >/dev/null
grep -F 'transform = 1' "$hyprctl_eval" >/dev/null

apply_result="$(
  PATH="$test_bin:$PATH" display_apply_request '{"preset":"external","primary":"DP-6"}'
)"
display_token="$(jq -r '.token' <<<"$apply_result")"
PATH="$test_bin:$PATH" display_rollback "$display_token"
test ! -e "$display_pending_file"
grep -F 'transform = 1' "$hyprctl_eval" >/dev/null

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

# Exercise telemetry arithmetic and ensure polling does not query sleeping GPUs.
bash "$source_root/tests/telemetry.sh" "$source_root"
