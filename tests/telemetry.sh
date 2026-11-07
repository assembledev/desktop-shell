#!/usr/bin/env bash
set -euo pipefail

source_root="${1:?source root is required}"
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT
state_dir="$test_root/state"
desktop_shell_state_dir="$state_dir"
system_sys_root="$test_root/sys"
system_proc_root="$test_root/proc"
mkdir -p "$state_dir" "$system_sys_root" "$system_proc_root/sys/kernel/random" "$test_root/bin"
TEST_JQ="$(command -v jq)"
export TEST_JQ
export TEST_JQ_CALLS="$test_root/jq-calls"
export TEST_GPU_CALLS="$test_root/gpu-calls"
TEST_SAMPLE_TIME=4000
battery_status=Discharging
battery_energy=40000000
battery_continuous=false
# Generated script expands these variables when invoked.
# shellcheck disable=SC2016
printf '%s\n' "#!$(command -v bash)" 'printf "call\n" >>"$TEST_JQ_CALLS"' 'exec "$TEST_JQ" "$@"' >"$test_root/bin/jq"
# Generated script expands these variables when invoked.
# shellcheck disable=SC2016
printf '%s\n' "#!$(command -v bash)" 'touch "$TEST_GPU_CALLS"' 'sleep "${TEST_GPU_DELAY:-0}"' 'printf "1024, 4096\n"' >"$test_root/bin/nvidia-smi"
chmod +x "$test_root/bin/"*
export PATH="$test_root/bin:$PATH"
# shellcheck source=../src/backend/lib/metrics.sh
source "$source_root/src/backend/lib/metrics.sh"

sample_battery() {
  : >"$TEST_JQ_CALLS"
  battery_analysis "{\"now\":$TEST_SAMPLE_TIME,\"continuous\":$battery_continuous,\"status\":\"$battery_status\",\"energyUwh\":$battery_energy}" >"$test_root/battery.json"
  test "$(wc -l <"$TEST_JQ_CALLS")" -eq 1 || {
    printf 'battery history must use one JSON processor\n' >&2
    exit 1
  }
}

printf 'test-boot\n' >"$system_proc_root/sys/kernel/random/boot_id"
sample_battery
"$TEST_JQ" -e '.bootSeconds == 0 and .bootWh == 0' "$test_root/battery.json" >/dev/null

# Quantized native readings contribute elapsed time without inventing energy.
battery_continuous=true
TEST_SAMPLE_TIME=4030
sample_battery
"$TEST_JQ" -e '.bootSeconds == 30 and .hourSeconds == 30 and .bootWh == 0' "$test_root/battery.json" >/dev/null
TEST_SAMPLE_TIME=4060
battery_energy=39900000
sample_battery
"$TEST_JQ" -e '.bootSeconds == 60 and .bootWh == 0.1 and .hourAverage == "6.0 W"' "$test_root/battery.json" >/dev/null

# Suspend, observer restart and wall-clock jumps invalidate only the baseline.
TEST_SAMPLE_TIME=4300
battery_energy=39000000
battery_continuous=false
sample_battery
"$TEST_JQ" -e '.bootSeconds == 60 and .bootWh == 0.1' "$test_root/battery.json" >/dev/null
battery_status=External
battery_continuous=true
sample_battery
TEST_SAMPLE_TIME=4330
battery_status=Discharging
sample_battery
TEST_SAMPLE_TIME=4360
battery_energy=39100000
sample_battery
"$TEST_JQ" -e '.bootSeconds == 60 and .bootWh == 0.1' "$test_root/battery.json" >/dev/null
TEST_SAMPLE_TIME=4390
battery_energy=39000000
sample_battery
"$TEST_JQ" -e '.bootSeconds == 90 and .bootWh == 0.2' "$test_root/battery.json" >/dev/null

# A five-minute awake interval between hardware updates is valid.
TEST_SAMPLE_TIME=4690
battery_energy=38500000
sample_battery
"$TEST_JQ" -e '.bootSeconds == 390 and .bootWh == 0.7' "$test_root/battery.json" >/dev/null
previous_state="$(cat "$state_dir/battery-drain.json")"
if battery_analysis '{"now":4700,"continuous":true,"status":"Discharging","energyUwh":-1}' >/dev/null 2>&1; then
  printf 'invalid battery sample accepted\n' >&2
  exit 1
fi
test "$(cat "$state_dir/battery-drain.json")" = "$previous_state"

# A backward clock jump drops future-dated rolling samples, not boot totals.
TEST_SAMPLE_TIME=4000
battery_continuous=false
sample_battery
"$TEST_JQ" -e '.bootWh == 0.7 and .bootSeconds == 390 and .hourSeconds == 0' "$test_root/battery.json" >/dev/null
battery_continuous=true

# Rolling-hour overlap, boot reset and damaged persistent state.
TEST_SAMPLE_TIME=4300
battery_status=External
printf '%s\n' '{"bootId":"test-boot","lastTs":4300,"lastEnergyUwh":39000000,"lastStatus":"External","totalWh":1,"totalSeconds":120,"history":[{"start":640,"end":760,"seconds":120,"wh":0},{"start":760,"end":790,"seconds":30,"wh":0.15}]}' >"$state_dir/battery-drain.json"
sample_battery
"$TEST_JQ" -e '.hourSeconds == 90 and .hourWh == 0.15 and .hourAverage == "6.0 W"' "$test_root/battery.json" >/dev/null
printf 'new-boot\n' >"$system_proc_root/sys/kernel/random/boot_id"
sample_battery
"$TEST_JQ" -e '.bootWh == 0 and .hourSeconds == 0' "$test_root/battery.json" >/dev/null
printf '{broken' >"$state_dir/battery-drain.json"
sample_battery
"$TEST_JQ" -e '.bootWh == 0' "$test_root/battery.json" >/dev/null

# GPU collection has no CPU/RAM reads or persistent sampling state.
export DESKTOP_SHELL_BAR_SHOW_VRAM=0
vram_json >"$test_root/vram.json"
test ! -e "$TEST_GPU_CALLS"
"$TEST_JQ" -e 'keys == ["hasVram","vram","vramText"] and .hasVram == false' "$test_root/vram.json" >/dev/null
export DESKTOP_SHELL_BAR_SHOW_VRAM=1
vram_json >"$test_root/vram.json"
test -e "$TEST_GPU_CALLS"
"$TEST_JQ" -e '.hasVram and .vram == 0.25 and .vramText == "1.0/4G"' "$test_root/vram.json" >/dev/null
mkdir -p "$system_sys_root/module/nvidia/drivers/pci:nvidia/test/power"
printf 'suspended\n' >"$system_sys_root/module/nvidia/drivers/pci:nvidia/test/power/runtime_status"
rm "$TEST_GPU_CALLS"
vram_json >"$test_root/vram.json"
"$TEST_JQ" -e '.hasVram == false' "$test_root/vram.json" >/dev/null
test ! -e "$TEST_GPU_CALLS"
printf 'active\n' >"$system_sys_root/module/nvidia/drivers/pci:nvidia/test/power/runtime_status"
TEST_GPU_DELAY=10 vram_json >"$test_root/vram.json"
"$TEST_JQ" -e '.hasVram == false' "$test_root/vram.json" >/dev/null

# Exercise the bar command with no procfs and no existing state directory.
cli_state="$test_root/cli-state"
config_file="$test_root/cli-config.json"
printf '%s\n' '{"bar":{"showVram":false,"workspaceIcons":false}}' >"$config_file"
rm -f "$TEST_GPU_CALLS"
DESKTOP_SHELL_CONFIG="$config_file" XDG_STATE_HOME="$cli_state" \
  DESKTOP_SHELL_SYS_ROOT="$system_sys_root" DESKTOP_SHELL_PROC_ROOT="$test_root/missing-proc" \
  bash "$source_root/src/backend/desktop-shell.sh" bar vram-json >"$test_root/vram.json"
"$TEST_JQ" -e '.hasVram == false' "$test_root/vram.json" >/dev/null
test ! -e "$cli_state"
test ! -e "$TEST_GPU_CALLS"

# Native battery history has no configuration or sysfs dependency.
printf '{broken' >"$config_file"
DESKTOP_SHELL_CONFIG="$config_file" XDG_STATE_HOME="$cli_state" \
  DESKTOP_SHELL_SYS_ROOT="$system_sys_root" DESKTOP_SHELL_PROC_ROOT="$system_proc_root" \
  bash "$source_root/src/backend/desktop-shell.sh" bar battery-analysis \
  '{"now":5000,"continuous":false,"status":"Discharging","energyUwh":40000000}' >"$test_root/cli-battery.json"
"$TEST_JQ" -e '.bootWh == 0 and .bootSeconds == 0' "$test_root/cli-battery.json" >/dev/null

# Explicit false must disable workspace icon work; omission keeps the default.
for policy in false true null; do
  printf '{"bar":{"workspaceIcons":%s}}\n' "$policy" >"$config_file"
  expected=1
  [ "$policy" != false ] || expected=0
  actual="$("$TEST_JQ" -j -f "$source_root/src/backend/lib/config-environment.jq" "$config_file" |
    tr '\0' '\n' | awk '/^DESKTOP_SHELL_BAR_WORKSPACE_ICONS$/ { getline; print; exit }')"
  test "$actual" = "$expected"
done
