#!/usr/bin/env bash

metrics_json() {
  cpu_file="$state_dir/cpu"
  read -r _ user nice system idle iowait irq softirq steal _ <"$system_proc_root/stat"
  steal="${steal:-0}"
  total=$((user + nice + system + idle + iowait + irq + softirq + steal))
  idle_all=$((idle + iowait))
  old_total="$total"
  old_idle="$idle_all"
  if [ -f "$cpu_file" ]; then
    read -r old_total old_idle <"$cpu_file" || true
  fi
  printf '%s %s\n' "$total" "$idle_all" >"$cpu_file"
  total_diff=$((total - old_total))
  idle_diff=$((idle_all - old_idle))

  # Hidden VRAM and runtime-suspended GPUs must not trigger an NVIDIA query.
  query_vram="${DESKTOP_SHELL_BAR_SHOW_VRAM:-1}"
  for runtime_status in "$system_sys_root"/module/nvidia/drivers/pci:nvidia/*/power/runtime_status; do
    [ -r "$runtime_status" ] || continue
    IFS= read -r gpu_status <"$runtime_status" || continue
    if [ "$gpu_status" != active ]; then
      query_vram=0
      break
    fi
  done
  vram_used=""
  vram_total=""
  if [ "$query_vram" != 0 ] && command -v nvidia-smi >/dev/null 2>&1; then
    vram_line="$(nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null || true)"
    IFS=, read -r vram_used vram_total <<<"$vram_line"
  fi

  # Read memory once and format all numeric fields in the same process.
  awk -v totalDiff="$total_diff" -v idleDiff="$idle_diff" \
    -v gpuUsed="$vram_used" -v gpuTotal="$vram_total" '
    /^MemTotal:/ { memTotal = $2 }
    /^MemAvailable:/ { memAvailable = $2 }
    END {
      cpu = totalDiff > 0 ? 1 - idleDiff / totalDiff : 0
      used = memTotal - memAvailable
      ram = memTotal > 0 ? used / memTotal : 0
      hasGpu = gpuTotal + 0 > 0
      vram = hasGpu ? gpuUsed / gpuTotal : 0
      vramText = hasGpu ? sprintf("%.1f/%.0fG", gpuUsed / 1024, gpuTotal / 1024) : "--"
      printf "{\"cpu\":%.3f,\"ram\":%.3f,\"ramText\":\"%.1f/%.0fG\",\"hasVram\":%s,\"vram\":%.3f,\"vramText\":\"%s\"}\n", \
        cpu, ram, used / 1024 / 1024, memTotal / 1024 / 1024, hasGpu ? "true" : "false", vram, vramText
    }
  ' "$system_proc_root/meminfo"
}

battery_energy_uwh() {
  bat="$1"

  if [ -r "$bat/energy_now" ]; then
    IFS= read -r energy <"$bat/energy_now" 2>/dev/null || energy=0
    printf '%s\n' "$energy"
    return
  fi

  if [ -r "$bat/charge_now" ] && [ -r "$bat/voltage_now" ]; then
    IFS= read -r charge_uah <"$bat/charge_now" 2>/dev/null || charge_uah=0
    IFS= read -r voltage_uv <"$bat/voltage_now" 2>/dev/null || voltage_uv=0
    awk -v charge="$charge_uah" -v voltage="$voltage_uv" 'BEGIN {
      if (charge > 0 && voltage > 0) {
        printf "%.0f\n", charge * voltage / 1000000
      } else {
        printf "0\n"
      }
    }'
    return
  fi

  printf '0\n'
}

battery_json() {
  bat=""
  for candidate in "$system_sys_root"/class/power_supply/BAT*; do
    if [ -e "$candidate" ]; then
      bat="$candidate"
      break
    fi
  done

  if [ -z "$bat" ]; then
    jq -nc '{available: false, capacity: 0, status: "", power: ""}'
    return
  fi

  IFS= read -r capacity <"$bat/capacity" 2>/dev/null || capacity=0
  IFS= read -r status <"$bat/status" 2>/dev/null || status=Unknown
  energy_uwh="$(battery_energy_uwh "$bat")"
  case "$capacity" in "" | *[!0-9]*) capacity=0 ;; esac
  case "$energy_uwh" in "" | *[!0-9]*) energy_uwh=0 ;; esac

  has_power=false
  power_uw=0
  if [ -r "$bat/power_now" ]; then
    has_power=true
    IFS= read -r power_uw <"$bat/power_now" 2>/dev/null || power_uw=0
    case "$power_uw" in "" | *[!0-9]*) power_uw=0 ;; esac
  fi

  now="$(date +%s)"
  IFS= read -r boot_id <"$system_proc_root/sys/kernel/random/boot_id" 2>/dev/null || boot_id=unknown
  state_file="$desktop_shell_state_dir/battery-drain.json"
  lock_file="$desktop_shell_state_dir/battery-drain.lock"
  exec 9>"$lock_file"
  flock 9

  state='{}'
  if [ -s "$state_file" ]; then
    state="$(<"$state_file")"
  fi

  # Compute history and presentation together rather than reparsing each field.
  result="$(jq -nc \
    --arg state "$state" \
    --arg bootId "$boot_id" \
    --arg status "$status" \
    --argjson hasPower "$has_power" \
    --argjson now "$now" \
    --argjson energy "$energy_uwh" \
    --argjson powerUw "$power_uw" \
    --argjson capacity "$capacity" \
    -f "${BASH_SOURCE[0]%/*}/battery-analysis.jq")" || return
  tmp_state="$(mktemp "$desktop_shell_state_dir/battery-drain.XXXXXX")"
  printf '%s\n' "${result%%$'\n'*}" >"$tmp_state"
  mv "$tmp_state" "$state_file"
  printf '%s\n' "${result#*$'\n'}"
}
