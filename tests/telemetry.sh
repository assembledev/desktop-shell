#!/usr/bin/env bash
set -euo pipefail

source_root="${1:?source root is required}"
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT
state_dir="$test_root/state"
desktop_shell_state_dir="$state_dir"
system_sys_root="$test_root/sys"
system_proc_root="$test_root/proc"
mkdir -p "$state_dir" "$system_sys_root/class/power_supply" "$system_proc_root/sys/kernel/random" "$test_root/bin"
TEST_JQ="$(command -v jq)"
export TEST_JQ
export TEST_JQ_CALLS="$test_root/jq-calls"
export TEST_GPU_CALLS="$test_root/gpu-calls"
export TEST_SAMPLE_TIME=4000
# Generated script expands these variables when invoked.
# shellcheck disable=SC2016
printf '%s\n' "#!$(command -v bash)" 'printf "call\n" >>"$TEST_JQ_CALLS"' 'exec "$TEST_JQ" "$@"' >"$test_root/bin/jq"
# Generated script expands these variables when invoked.
# shellcheck disable=SC2016
printf '%s\n' "#!$(command -v bash)" 'printf "%s\n" "$TEST_SAMPLE_TIME"' >"$test_root/bin/date"
# Generated script expands these variables when invoked.
# shellcheck disable=SC2016
printf '%s\n' "#!$(command -v bash)" 'touch "$TEST_GPU_CALLS"' 'printf "1024, 4096\n"' >"$test_root/bin/nvidia-smi"
chmod +x "$test_root/bin/"*
export PATH="$test_root/bin:$PATH"
# shellcheck source=../src/backend/lib/metrics.sh
source "$source_root/src/backend/lib/metrics.sh"

sample_battery() {
  : >"$TEST_JQ_CALLS"
  battery_json >"$test_root/battery.json"
  test "$(wc -l <"$TEST_JQ_CALLS")" -eq 1 || {
    printf 'battery sampling must use one JSON processor\n' >&2
    exit 1
  }
}

sample_battery
"$TEST_JQ" -e '.available == false' "$test_root/battery.json" >/dev/null
bat_dir="$system_sys_root/class/power_supply/BAT0"
mkdir -p "$bat_dir"
printf '80\n' >"$bat_dir/capacity"
printf 'Discharging\n' >"$bat_dir/status"
printf '40000000\n' >"$bat_dir/energy_now"
printf '10000000\n' >"$bat_dir/power_now"
printf 'test-boot\n' >"$system_proc_root/sys/kernel/random/boot_id"
sample_battery
"$TEST_JQ" -e '.analysis.estimateSeconds == 14400 and .analysis.estimateText == "4h 00m" and .analysis.currentDraw == "10.0 W" and .analysis.bootSeconds == 0' "$test_root/battery.json" >/dev/null

# A 30-second discharge sample contributes to both rolling and boot totals.
export TEST_SAMPLE_TIME=4030
printf '39900000\n' >"$bat_dir/energy_now"
sample_battery
"$TEST_JQ" -e '.analysis.bootSeconds == 30 and .analysis.hourSeconds == 30 and .analysis.bootWh == 0.1 and .analysis.bootAverage == "12.0 W" and .analysis.estimateSeconds == 11970' "$test_root/battery.json" >/dev/null

# Ignore suspend gaps and charging transitions rather than inventing draw.
export TEST_SAMPLE_TIME=4300
printf '39000000\n' >"$bat_dir/energy_now"
sample_battery
"$TEST_JQ" -e '.analysis.bootSeconds == 30 and .analysis.bootWh == 0.1' "$test_root/battery.json" >/dev/null
printf 'Charging\n' >"$bat_dir/status"
sample_battery
"$TEST_JQ" -e '.analysis.estimateText == "charging" and .analysis.currentDraw == "--" and .analysis.estimateSeconds == 0' "$test_root/battery.json" >/dev/null

# Keep only the overlapping part of a sample at the rolling-hour boundary.
printf '%s\n' '{"bootId":"test-boot","lastTs":4300,"lastEnergyUwh":39000000,"lastStatus":"Charging","totalWh":1,"totalSeconds":120,"history":[{"start":640,"end":760,"seconds":120,"wh":1}]}' >"$state_dir/battery-drain.json"
sample_battery
"$TEST_JQ" -e '.analysis.hourSeconds == 60 and .analysis.hourWh == 0.5 and .analysis.hourAverage == "30.0 W"' "$test_root/battery.json" >/dev/null
printf 'new-boot\n' >"$system_proc_root/sys/kernel/random/boot_id"
sample_battery
"$TEST_JQ" -e '.analysis.bootWh == 0 and .analysis.hourSeconds == 0' "$test_root/battery.json" >/dev/null
printf '{broken' >"$state_dir/battery-drain.json"
sample_battery
"$TEST_JQ" -e '.analysis.bootWh == 0' "$test_root/battery.json" >/dev/null

# Devices reporting charge/voltage instead of energy remain supported.
rm "$bat_dir/energy_now" "$bat_dir/power_now"
printf '4000000\n' >"$bat_dir/charge_now"
printf '10000000\n' >"$bat_dir/voltage_now"
printf 'Discharging\n' >"$bat_dir/status"
sample_battery
"$TEST_JQ" -e '.power == "" and .analysis.estimateSeconds == 0' "$test_root/battery.json" >/dev/null
"$TEST_JQ" -e '.lastEnergyUwh == 40000000' "$state_dir/battery-drain.json" >/dev/null
printf 'Full\n' >"$bat_dir/status"
sample_battery
"$TEST_JQ" -e '.analysis.estimateText == "full"' "$test_root/battery.json" >/dev/null

# CPU deltas, memory formatting, and GPU visibility keep their JSON contract.
printf 'cpu 100 0 100 800 0 0 0 0\n' >"$system_proc_root/stat"
printf 'MemTotal: 8388608 kB\nMemAvailable: 4194304 kB\n' >"$system_proc_root/meminfo"
export DESKTOP_SHELL_BAR_SHOW_VRAM=0
metrics_json >"$test_root/metrics.json"
test ! -e "$TEST_GPU_CALLS"
"$TEST_JQ" -e '.cpu == 0 and .ram == 0.5 and .ramText == "4.0/8G" and .hasVram == false' "$test_root/metrics.json" >/dev/null
printf 'cpu 150 0 100 850 0 0 0 0\n' >"$system_proc_root/stat"
export DESKTOP_SHELL_BAR_SHOW_VRAM=1
metrics_json >"$test_root/metrics.json"
test -e "$TEST_GPU_CALLS"
"$TEST_JQ" -e '.cpu == 0.5 and .hasVram == true and .vram == 0.25 and .vramText == "1.0/4G"' "$test_root/metrics.json" >/dev/null
rm "$TEST_GPU_CALLS"
mkdir -p "$system_sys_root/module/nvidia/drivers/pci:nvidia/test/power"
printf 'suspended\n' >"$system_sys_root/module/nvidia/drivers/pci:nvidia/test/power/runtime_status"
metrics_json >"$test_root/metrics.json"
test ! -e "$TEST_GPU_CALLS"
"$TEST_JQ" -e '.hasVram == false' "$test_root/metrics.json" >/dev/null
printf 'active\n' >"$system_sys_root/module/nvidia/drivers/pci:nvidia/test/power/runtime_status"
metrics_json >"$test_root/metrics.json"
test -e "$TEST_GPU_CALLS"
"$TEST_JQ" -e '.hasVram == true' "$test_root/metrics.json" >/dev/null
