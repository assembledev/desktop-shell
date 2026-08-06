#!/usr/bin/env bash

metrics_json() {
  cpu_file="$state_dir/cpu"
  cpu_line="$(grep '^cpu ' "$system_proc_root/stat")"
  read -r _ user nice system idle iowait irq softirq steal _ <<<"$cpu_line"
  steal="${steal:-0}"
  total=$((user + nice + system + idle + iowait + irq + softirq + steal))
  idle_all=$((idle + iowait))
  if [ -f "$cpu_file" ]; then
    read -r old_total old_idle <"$cpu_file" || true
  else
    old_total="$total"
    old_idle="$idle_all"
  fi
  printf '%s %s\n' "$total" "$idle_all" >"$cpu_file"
  total_diff=$((total - old_total))
  idle_diff=$((idle_all - old_idle))
  cpu="0"
  if [ "$total_diff" -gt 0 ]; then
    cpu="$(awk -v total="$total_diff" -v idle="$idle_diff" 'BEGIN { printf "%.3f", 1 - idle / total }')"
  fi

  mem_total="$(awk '/^MemTotal:/ { print $2 }' "$system_proc_root/meminfo")"
  mem_avail="$(awk '/^MemAvailable:/ { print $2 }' "$system_proc_root/meminfo")"
  mem_used=$((mem_total - mem_avail))
  ram="$(awk -v used="$mem_used" -v total="$mem_total" 'BEGIN { if (total > 0) printf "%.3f", used / total; else printf "0" }')"
  ram_text="$(awk -v used="$mem_used" -v total="$mem_total" 'BEGIN { printf "%.1f/%.0fG", used / 1024 / 1024, total / 1024 / 1024 }')"

  if command -v nvidia-smi >/dev/null 2>&1; then
    vram_line="$(nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null | head -n 1 || true)"
  else
    vram_line=""
  fi

  if [ -n "$vram_line" ]; then
    used="$(printf '%s\n' "$vram_line" | cut -d, -f1 | tr -d ' ')"
    total_v="$(printf '%s\n' "$vram_line" | cut -d, -f2 | tr -d ' ')"
    vram="$(awk -v used="$used" -v total="$total_v" 'BEGIN { if (total > 0) printf "%.3f", used / total; else printf "0" }')"
    vram_text="$(awk -v used="$used" -v total="$total_v" 'BEGIN { printf "%.1f/%.0fG", used / 1024, total / 1024 }')"
    has_vram=true
  else
    vram="0"
    vram_text="--"
    has_vram=false
  fi

  jq -n \
    --argjson cpu "$cpu" \
    --argjson ram "$ram" \
    --arg ramText "$ram_text" \
    --argjson hasVram "$has_vram" \
    --argjson vram "$vram" \
    --arg vramText "$vram_text" \
    '{cpu: $cpu, ram: $ram, ramText: $ramText, hasVram: $hasVram, vram: $vram, vramText: $vramText}'
}

battery_energy_uwh() {
  bat="$1"

  if [ -r "$bat/energy_now" ]; then
    cat "$bat/energy_now" 2>/dev/null || printf '0\n'
    return
  fi

  if [ -r "$bat/charge_now" ] && [ -r "$bat/voltage_now" ]; then
    charge_uah="$(cat "$bat/charge_now" 2>/dev/null || printf 0)"
    voltage_uv="$(cat "$bat/voltage_now" 2>/dev/null || printf 0)"
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

battery_format_watts() {
  wh="$1"
  seconds="$2"

  awk -v wh="$wh" -v seconds="$seconds" 'BEGIN {
    if (wh > 0 && seconds > 0) {
      printf "%.1f W\n", wh * 3600 / seconds
    } else {
      printf "--\n"
    }
  }'
}

battery_format_seconds() {
  seconds="$1"

  awk -v seconds="$seconds" 'BEGIN {
    if (seconds <= 0) {
      printf "--\n"
      exit
    }

    minutes = int(seconds / 60 + 0.5)
    hours = int(minutes / 60)
    minutes = minutes % 60
    if (hours > 0) {
      printf "%dh %02dm\n", hours, minutes
    } else {
      printf "%dm\n", minutes
    }
  }'
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

  capacity="$(cat "$bat/capacity" 2>/dev/null || printf 0)"
  status="$(cat "$bat/status" 2>/dev/null || printf Unknown)"
  energy_uwh="$(battery_energy_uwh "$bat")"
  case "$capacity" in "" | *[!0-9]*) capacity=0 ;; esac
  case "$energy_uwh" in "" | *[!0-9]*) energy_uwh=0 ;; esac

  power=""
  power_uw=0
  if [ -r "$bat/power_now" ]; then
    power_uw="$(cat "$bat/power_now" 2>/dev/null || printf 0)"
    case "$power_uw" in "" | *[!0-9]*) power_uw=0 ;; esac
    power="$(awk -v power="$power_uw" 'BEGIN { printf "%.1fW", power / 1000000 }')"
  fi

  now="$(date +%s)"
  boot_id="$(cat "$system_proc_root/sys/kernel/random/boot_id" 2>/dev/null || printf unknown)"
  state_file="$desktop_shell_state_dir/battery-drain.json"
  lock_file="$desktop_shell_state_dir/battery-drain.lock"
  exec 9>"$lock_file"
  flock 9

  state="$(
    if [ -s "$state_file" ]; then
      cat "$state_file"
    else
      printf '{}\n'
    fi
  )"

  state_boot="$(printf '%s\n' "$state" | jq -r '.bootId // ""' 2>/dev/null || true)"
  if [ "$state_boot" = "$boot_id" ]; then
    prev_ts="$(printf '%s\n' "$state" | jq -r '.lastTs // 0' 2>/dev/null || printf 0)"
    prev_energy="$(printf '%s\n' "$state" | jq -r '.lastEnergyUwh // 0' 2>/dev/null || printf 0)"
    prev_status="$(printf '%s\n' "$state" | jq -r '.lastStatus // ""' 2>/dev/null || true)"
    total_wh="$(printf '%s\n' "$state" | jq -r '.totalWh // 0' 2>/dev/null || printf 0)"
    total_seconds="$(printf '%s\n' "$state" | jq -r '.totalSeconds // 0' 2>/dev/null || printf 0)"
    history_json="$(printf '%s\n' "$state" | jq -c '.history // []' 2>/dev/null || printf '[]')"
  else
    prev_ts=0
    prev_energy=0
    prev_status=""
    total_wh=0
    total_seconds=0
    history_json='[]'
  fi

  case "$prev_ts" in "" | *[!0-9]*) prev_ts=0 ;; esac
  case "$prev_energy" in "" | *[!0-9]*) prev_energy=0 ;; esac
  case "$total_seconds" in "" | *[!0-9]*) total_seconds=0 ;; esac
  if ! printf '%s\n' "$total_wh" | grep -Eq '^[0-9]+([.][0-9]+)?$'; then
    total_wh=0
  fi

  max_sample_gap_seconds=120
  delta_seconds=0
  delta_wh=0
  if [ "$status" = "Discharging" ] && [ "$prev_status" = "Discharging" ] && [ "$energy_uwh" -gt 0 ] && [ "$prev_energy" -gt "$energy_uwh" ] && [ "$now" -gt "$prev_ts" ] && [ "$((now - prev_ts))" -le "$max_sample_gap_seconds" ]; then
    delta_seconds="$((now - prev_ts))"
    delta_uwh="$((prev_energy - energy_uwh))"
    delta_wh="$(awk -v uwh="$delta_uwh" 'BEGIN { printf "%.9f\n", uwh / 1000000 }')"
    total_wh="$(awk -v total="$total_wh" -v delta="$delta_wh" 'BEGIN { printf "%.9f\n", total + delta }')"
    total_seconds="$((total_seconds + delta_seconds))"
  fi

  cutoff="$((now - 3600))"
  if [ "$delta_seconds" -gt 0 ]; then
    history_json="$(
      printf '%s\n' "$history_json" |
        jq -c \
          --argjson start "$prev_ts" \
          --argjson end "$now" \
          --argjson seconds "$delta_seconds" \
          --argjson wh "$delta_wh" \
          --argjson cutoff "$cutoff" \
          '. + [{start: $start, end: $end, seconds: $seconds, wh: $wh}] | map(select((.end // 0) >= $cutoff))'
    )"
  else
    history_json="$(
      printf '%s\n' "$history_json" |
        jq -c --argjson cutoff "$cutoff" 'map(select((.end // 0) >= $cutoff))'
    )"
  fi

  hour_aggregate="$(
    printf '%s\n' "$history_json" |
      jq -c --argjson now "$now" '
          ($now - 3600) as $cutoff
          | reduce .[] as $sample ({wh: 0, seconds: 0};
              ($sample.start // (($sample.end // 0) - ($sample.seconds // 0))) as $start
              | ($sample.end // 0) as $end
              | if $end > $cutoff and $end > $start then
                  ([$start, $cutoff] | max) as $overlapStart
                  | ($end - $overlapStart) as $overlap
                  | .wh += (($sample.wh // 0) * ($overlap / ($end - $start)))
                  | .seconds += $overlap
                else
                  .
                end
            )
        '
  )"
  hour_wh="$(printf '%s\n' "$hour_aggregate" | jq -r '.wh // 0')"
  hour_seconds="$(printf '%s\n' "$hour_aggregate" | jq -r '.seconds // 0')"

  boot_average="$(battery_format_watts "$total_wh" "$total_seconds")"
  hour_average="$(battery_format_watts "$hour_wh" "$hour_seconds")"
  if [ "$status" = "Discharging" ] && [ "$power_uw" -gt 0 ]; then
    current_draw="$(awk -v power="$power_uw" 'BEGIN { printf "%.1f W\n", power / 1000000 }')"
  else
    current_draw="--"
  fi

  estimate_seconds=0
  estimate_text="--"
  if [ "$status" = "Discharging" ] && [ "$energy_uwh" -gt 0 ]; then
    estimate_seconds="$(awk -v energy="$energy_uwh" -v hourWh="$hour_wh" -v hourSeconds="$hour_seconds" -v power="$power_uw" 'BEGIN {
      if (hourWh > 0 && hourSeconds > 0) {
        printf "%.0f\n", energy / 1000000 * hourSeconds / hourWh
      } else if (power > 0) {
        printf "%.0f\n", energy * 3600 / power
      } else {
        printf "0\n"
      }
    }')"
    estimate_text="$(battery_format_seconds "$estimate_seconds")"
  elif [ "$status" = "Charging" ]; then
    estimate_text="charging"
  elif [ "$status" = "Full" ]; then
    estimate_text="full"
  fi

  tmp_state="$(mktemp "$desktop_shell_state_dir/battery-drain.XXXXXX")"
  jq -nc \
    --arg bootId "$boot_id" \
    --arg status "$status" \
    --argjson lastTs "$now" \
    --argjson lastEnergyUwh "$energy_uwh" \
    --argjson totalWh "$total_wh" \
    --argjson totalSeconds "$total_seconds" \
    --argjson history "$history_json" \
    '{
      bootId: $bootId,
      lastTs: $lastTs,
      lastStatus: $status,
      lastEnergyUwh: $lastEnergyUwh,
      totalWh: $totalWh,
      totalSeconds: $totalSeconds,
      history: $history
    }' >"$tmp_state"
  mv "$tmp_state" "$state_file"

  jq -nc \
    --argjson capacity "$capacity" \
    --arg status "$status" \
    --arg power "$power" \
    --arg estimateText "$estimate_text" \
    --arg currentDraw "$current_draw" \
    --arg bootAverage "$boot_average" \
    --arg hourAverage "$hour_average" \
    --argjson estimateSeconds "$estimate_seconds" \
    --argjson bootWh "$total_wh" \
    --argjson bootSeconds "$total_seconds" \
    --argjson hourWh "$hour_wh" \
    --argjson hourSeconds "$hour_seconds" \
    '{
      available: true,
      capacity: $capacity,
      status: $status,
      power: $power,
      analysis: {
        estimateText: $estimateText,
        estimateSeconds: $estimateSeconds,
        currentDraw: $currentDraw,
        bootAverage: $bootAverage,
        hourAverage: $hourAverage,
        bootWh: $bootWh,
        bootSeconds: $bootSeconds,
        hourWh: $hourWh,
        hourSeconds: $hourSeconds
      }
    }'
}
