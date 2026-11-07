#!/usr/bin/env bash

vram_json() {
  local query_vram runtime_status gpu_status vram_used vram_total vram_line
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
    vram_line="$(timeout --kill-after=1s 3s nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null || true)"
    IFS=, read -r vram_used vram_total <<<"$vram_line"
  fi
  awk -v used="$vram_used" -v total="$vram_total" 'BEGIN {
    numeric = "^[[:space:]]*[0-9]+([.][0-9]+)?[[:space:]]*$"
    available = used ~ numeric && total ~ numeric && total + 0 > 0 && used + 0 <= total + 0
    ratio = available ? used / total : 0
    label = available ? sprintf("%.1f/%.0fG", used / 1024, total / 1024) : "--"
    printf "{\"hasVram\":%s,\"vram\":%.3f,\"vramText\":\"%s\"}\n", available ? "true" : "false", ratio, label
  }'
}

battery_analysis() {
  IFS= read -r boot_id <"$system_proc_root/sys/kernel/random/boot_id" 2>/dev/null || boot_id=unknown
  state_file="$desktop_shell_state_dir/battery-drain.json"
  lock_file="$desktop_shell_state_dir/battery-drain.lock"
  exec 9>"$lock_file"
  flock 9

  state='{}'
  if [ -s "$state_file" ]; then
    state="$(<"$state_file")"
  fi

  result="$(jq -nc \
    --arg state "$state" \
    --arg bootId "$boot_id" \
    --argjson sample "${1:?battery sample is required}" \
    -f "${BASH_SOURCE[0]%/*}/battery-analysis.jq")" || return
  tmp_state="$(mktemp "$desktop_shell_state_dir/battery-drain.XXXXXX")"
  printf '%s\n' "${result%%$'\n'*}" >"$tmp_state"
  mv "$tmp_state" "$state_file"
  printf '%s\n' "${result#*$'\n'}"
}
