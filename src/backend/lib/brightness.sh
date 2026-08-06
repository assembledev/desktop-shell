#!/usr/bin/env bash

if [ -n "${XDG_RUNTIME_DIR:-}" ]; then
  brightness_runtime_dir="$XDG_RUNTIME_DIR/desktop-shell"
else
  brightness_runtime_dir="$desktop_shell_state_dir/runtime"
fi
brightness_target_cache="$brightness_runtime_dir/brightness-target"
brightness_idle_state="$brightness_runtime_dir/brightness-idle"
brightness_value_file="$brightness_runtime_dir/brightness-value"
brightness_lock_file="$brightness_runtime_dir/brightness.lock"
mkdir -p "$brightness_runtime_dir"

brightness_device_dir() {
  for device in "$system_sys_root"/class/backlight/*; do
    if [ -r "$device/max_brightness" ] && { [ -r "$device/actual_brightness" ] || [ -r "$device/brightness" ]; }; then
      printf '%s\n' "$device"
      return 0
    fi
  done
  return 1
}

brightness_backlight_values() {
  device="${1:-}"
  if [ -z "$device" ]; then
    device="$(brightness_device_dir)" || return 1
  fi
  current_file="$device/brightness"
  [ -r "$current_file" ] || current_file="$device/actual_brightness"
  IFS= read -r current <"$current_file" || return 1
  IFS= read -r max <"$device/max_brightness" || return 1
  case "$current:$max" in
    *[!0-9:]* | :* | *: | *:0) return 1 ;;
  esac
  printf 'backlight\t%s\t%s\t%s\n' "$device" "$current" "$max"
}

brightness_focused_output() {
  ensure_hypr_env
  hyprctl monitors -j 2>/dev/null |
    jq -r '[.[] | select(.focused == true) | .name][0] // empty' 2>/dev/null
}

brightness_ddc_detect_records() {
  ddcutil detect --brief 2>/dev/null | awk '
    function emit() {
      if (bus != "")
        print bus "\t" connector
    }
    /^[[:space:]]*Display [0-9]+/ {
      emit()
      bus = ""
      connector = ""
      next
    }
    /I2C bus:[[:space:]]*\/dev\/i2c-[0-9]+/ {
      value = $0
      sub(/^.*\/dev\/i2c-/, "", value)
      sub(/[^0-9].*$/, "", value)
      bus = value
      next
    }
    /DRM connector:/ {
      value = $0
      sub(/^.*DRM connector:[[:space:]]*/, "", value)
      sub(/[[:space:]].*$/, "", value)
      connector = value
    }
    END { emit() }
  '
}

brightness_ddc_target_bus() {
  if [ -r "$brightness_target_cache" ]; then
    IFS=$'\t' read -r cached_bus _ <"$brightness_target_cache" || true
    if [ -n "${cached_bus:-}" ] && [ -c "/dev/i2c-$cached_bus" ]; then
      printf '%s\n' "$cached_bus"
      return 0
    fi
    rm -f "$brightness_target_cache"
  fi

  records="$(brightness_ddc_detect_records)" || return 1
  count="$(printf '%s\n' "$records" | awk 'NF { count++ } END { print count + 0 }')"
  if [ "$count" -eq 0 ]; then
    printf 'desktop-shell: no DDC-capable display detected\n' >&2
    return 1
  fi

  if [ "$count" -eq 1 ]; then
    selected="$(printf '%s\n' "$records" | awk 'NF { print; exit }')"
  else
    focused="$(brightness_focused_output || true)"
    selected="$(
      printf '%s\n' "$records" |
        awk -F '\t' -v output="$focused" '
          output != "" && ($2 == output || $2 ~ ("-" output "$")) { print; exit }
        '
    )"
    if [ -z "$selected" ]; then
      printf 'desktop-shell: multiple DDC displays detected and focused output could not be resolved\n' >&2
      return 1
    fi
  fi

  IFS=$'\t' read -r bus connector <<<"$selected"
  case "$bus" in
    '' | *[!0-9]*) return 1 ;;
  esac
  target_tmp="$brightness_target_cache.$$"
  printf '%s\t%s\n' "$bus" "$connector" >"$target_tmp"
  mv -f "$target_tmp" "$brightness_target_cache"
  printf '%s\n' "$bus"
}

brightness_ddc_values_on_bus() {
  bus="$1"
  output="$(ddcutil --terse --bus "$bus" getvcp 10 2>/dev/null)" || return 1
  values="$(
    printf '%s\n' "$output" | awk '
      $1 == "VCP" {
        code = toupper($2)
        sub(/^0X/, "", code)
        if (code == "10" && $3 == "C") {
          print $4, $5
          exit
        }
      }
    '
  )"
  if [ -z "$values" ]; then
    values="$(
      printf '%s\n' "$output" |
        sed -nE 's/.*current value[[:space:]]*=[[:space:]]*([0-9]+),[[:space:]]*max value[[:space:]]*=[[:space:]]*([0-9]+).*/\1 \2/p' |
        head -n 1
    )"
  fi
  read -r current max <<<"$values"
  case "${current:-}:${max:-}" in
    *[!0-9:]* | :* | *: | *:0) return 1 ;;
  esac
  printf 'ddc\t%s\t%s\t%s\n' "$bus" "$current" "$max"
}

brightness_ddc_values() {
  attempt=1
  while [ "$attempt" -le 2 ]; do
    bus="$(brightness_ddc_target_bus)" || return 1
    if brightness_ddc_values_on_bus "$bus"; then
      return 0
    fi
    rm -f "$brightness_target_cache"
    attempt=$((attempt + 1))
  done
  printf 'desktop-shell: DDC brightness query failed\n' >&2
  return 1
}

brightness_target_values() {
  if device="$(brightness_device_dir)"; then
    brightness_backlight_values "$device"
  else
    brightness_ddc_values
  fi
}

brightness_backend() {
  if brightness_device_dir >/dev/null; then
    printf 'backlight\n'
    return 0
  fi
  if brightness_ddc_target_bus >/dev/null 2>&1; then
    printf 'ddc\n'
    return 0
  fi
  printf 'unavailable\n'
  return 3
}

brightness_capabilities_json() {
  if device="$(brightness_device_dir)"; then
    writable=false
    [ -w "$device/brightness" ] && writable=true
    jq -nc --arg backend backlight --argjson writable "$writable" \
      '{supported: true, backend: $backend, writable: $writable}'
    return 0
  fi

  if bus="$(brightness_ddc_target_bus 2>/dev/null)"; then
    writable=false
    [ -w "/dev/i2c-$bus" ] && writable=true
    jq -nc --arg backend ddc --argjson writable "$writable" \
      '{supported: true, backend: $backend, writable: $writable}'
    return 0
  fi

  jq -nc '{supported: false, backend: "", writable: false}'
}

brightness_percent() {
  current="$1"
  max="$2"
  printf '%s\n' "$(((current * 100 + max / 2) / max))"
}

brightness_publish() {
  value="$1"
  value_tmp="$brightness_value_file.$$"
  printf '%s\n' "$value" >"$value_tmp"
  mv -f "$value_tmp" "$brightness_value_file"
}

brightness_get() {
  values="$(brightness_target_values)" || return 1
  IFS=$'\t' read -r _ _ current max <<<"$values"
  brightness_percent "$current" "$max"
}

brightness_set_raw() {
  backend="$1"
  target="$2"
  raw="$3"
  case "$backend" in
    backlight)
      [ -d "$target" ] || return 1
      brightnessctl -c backlight -d "${target##*/}" set "$raw" >/dev/null
      ;;
    ddc)
      [ -c "/dev/i2c-$target" ] || return 1
      ddcutil --bus "$target" setvcp 10 "$raw" >/dev/null
      ;;
    *) return 1 ;;
  esac
}

brightness_idle_restore_locked() {
  [ -r "$brightness_idle_state" ] || return 0
  IFS=$'\t' read -r backend target current max <"$brightness_idle_state" || return 1
  case "${current:-}:${max:-}" in
    *[!0-9:]* | :* | *: | *:0) return 1 ;;
  esac

  if { [ "$backend" = backlight ] && [ ! -d "$target" ]; } ||
    { [ "$backend" = ddc ] && [ ! -c "/dev/i2c-$target" ]; }; then
    rm -f "$brightness_idle_state"
    return 0
  fi

  brightness_set_raw "$backend" "$target" "$current" || return 1
  rm -f "$brightness_idle_state"
  brightness_publish "$(brightness_percent "$current" "$max")"
}

brightness_set_percent_locked() {
  percent="$1"
  case "$percent" in
    '' | *[!0-9]*) return 2 ;;
  esac
  if [ "$percent" -lt 0 ] || [ "$percent" -gt 100 ]; then
    return 2
  fi

  brightness_idle_restore_locked || return 1
  values="$(brightness_target_values)" || return 1
  IFS=$'\t' read -r backend target _ max <<<"$values"
  raw="$(((percent * max + 50) / 100))"
  if [ "$percent" -gt 0 ] && [ "$raw" -eq 0 ]; then
    raw=1
  fi
  brightness_set_raw "$backend" "$target" "$raw" || return 1
  brightness_publish "$(brightness_percent "$raw" "$max")"
}

brightness_set() {
  exec 9>"$brightness_lock_file"
  flock 9
  brightness_set_percent_locked "$1"
}

brightness_adjust() {
  delta="$1"
  case "$delta" in
    -5 | 5) ;;
    *) return 2 ;;
  esac
  exec 9>"$brightness_lock_file"
  flock 9
  brightness_idle_restore_locked || return 1
  values="$(brightness_target_values)" || return 1
  IFS=$'\t' read -r backend target current max <<<"$values"
  percent="$(brightness_percent "$current" "$max")"
  percent=$((percent + delta))
  [ "$percent" -ge 0 ] || percent=0
  [ "$percent" -le 100 ] || percent=100
  raw="$(((percent * max + 50) / 100))"
  if [ "$percent" -gt 0 ] && [ "$raw" -eq 0 ]; then
    raw=1
  fi
  brightness_set_raw "$backend" "$target" "$raw" || return 1
  brightness_publish "$(brightness_percent "$raw" "$max")"
}

brightness_idle_dim() {
  exec 9>"$brightness_lock_file"
  flock 9
  [ ! -r "$brightness_idle_state" ] || return 0

  values="$(brightness_target_values)" || return 1
  IFS=$'\t' read -r backend target current max <<<"$values"
  drop="$(((max * 20 + 50) / 100))"
  minimum="$(((max + 99) / 100))"
  dimmed=$((current - drop))
  [ "$dimmed" -ge "$minimum" ] || dimmed="$minimum"

  idle_tmp="$brightness_idle_state.$$"
  printf '%s\t%s\t%s\t%s\n' "$backend" "$target" "$current" "$max" >"$idle_tmp"
  mv -f "$idle_tmp" "$brightness_idle_state"
  if ! brightness_set_raw "$backend" "$target" "$dimmed"; then
    rm -f "$brightness_idle_state"
    return 1
  fi
  brightness_publish "$(brightness_percent "$dimmed" "$max")"
}

brightness_idle_restore() {
  exec 9>"$brightness_lock_file"
  flock 9
  brightness_idle_restore_locked
}

brightness_watch_backlight() {
  last="$(brightness_get)" || return 1
  printf '%s\n' "$last"

  while IFS= read -r event; do
    case "$event" in
      KERNEL*change*backlight* | UDEV*change*backlight*)
        next="$(brightness_get)" || continue
        if [ "$next" != "$last" ]; then
          printf '%s\n' "$next"
          last="$next"
        fi
        ;;
    esac
  done < <(udevadm monitor --udev --kernel --subsystem-match=backlight 2>/dev/null)
}

brightness_watch_ddc() {
  last="$(brightness_get)" || return 1
  brightness_publish "$last"
  printf '%s\n' "$last"

  while sleep 0.25; do
    [ -r "$brightness_value_file" ] || continue
    IFS= read -r next <"$brightness_value_file" || continue
    case "$next" in
      '' | *[!0-9]*) continue ;;
    esac
    if [ "$next" != "$last" ]; then
      printf '%s\n' "$next"
      last="$next"
    fi
  done
}

brightness_watch() {
  case "$(brightness_backend 2>/dev/null || true)" in
    backlight) brightness_watch_backlight ;;
    ddc) brightness_watch_ddc ;;
    *) return 3 ;;
  esac
}
