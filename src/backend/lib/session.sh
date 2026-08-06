#!/usr/bin/env bash

keyboard_json() {
  ensure_hypr_env
  hyprctl devices -j 2>/dev/null |
    jq -c '
        (.keyboards // [] | map(select(.main == true))[0]) as $kb
        | {
            name: ($kb.name // ""),
            layout: ($kb.layout // ""),
            active: ($kb.active_keymap // "Unknown"),
            index: ($kb.active_layout_index // 0)
          }
      ' 2>/dev/null || jq -nc '{layout: "", active: "Unknown"}'
}

keyboard_set_layout() {
  ensure_hypr_env
  keyboard="${1:-}"
  index="${2:-}"
  [ -n "$keyboard" ] || exit 0
  printf '%s\n' "$index" | grep -Eq '^[0-9]+$' || exit 0
  hyprctl switchxkblayout -- "$keyboard" "$index" >/dev/null 2>&1 || true
}

calendar_popup() {
  quickshell ipc --path "${DESKTOP_SHELL_QML}"/shell.qml call calendar toggle >/dev/null 2>&1
}

session_action() {
  case "${1:-}" in
    lock) "$desktop_shell_executable" lock ;;
    sleep) systemctl suspend ;;
    restart) systemctl reboot ;;
    shutdown) systemctl poweroff ;;
  esac
}

power_status_json() {
  profile_file="$system_sys_root/firmware/acpi/platform_profile"
  choices_file="$system_sys_root/firmware/acpi/platform_profile_choices"
  if [ -r "$profile_file" ] && [ -r "$choices_file" ]; then
    profile="$(cat "$profile_file")"
    choices="$(cat "$choices_file")"
    writable=false
    [ -n "$privileged_helper" ] && writable=true
    printf '%s\n' "$choices" |
      jq -R --arg profile "$profile" --argjson writable "$writable" \
        '{supported: true, writable: $writable, profile: $profile, choices: (split(" ") | map(select(length > 0)))}'
  else
    jq -n '{supported: false, writable: false, profile: "", choices: []}'
  fi
}

power_set_profile() {
  profile="${1:-}"
  case "$profile" in
    "" | *[!A-Za-z0-9_-]*) return 2 ;;
  esac

  choices_file="$system_sys_root/firmware/acpi/platform_profile_choices"
  [ -r "$choices_file" ] || return 1
  tr ' ' '\n' <"$choices_file" | grep -Fx -- "$profile" >/dev/null || {
    printf 'desktop-shell: unsupported platform profile: %s\n' "$profile" >&2
    return 2
  }
  run_privileged platform-profile "$profile"
}

bar_ipc() {
  method="$1"
  case "$method" in
    show) ipc_method=reveal ;;
    hide) ipc_method=conceal ;;
    *) ipc_method="$method" ;;
  esac
  quickshell ipc --path "${DESKTOP_SHELL_QML}"/shell.qml call desktopBar "$ipc_method" >/dev/null 2>&1
}

bar_show() {
  bar_ipc show || true
}

bar_hide() {
  bar_ipc hide || true
}

focus_restore() {
  focus=0
  [ -f "$state_dir/focus" ] && focus="$(cat "$state_dir/focus")"
  if [ "$focus" = 1 ]; then
    bar_hide
  else
    bar_show
  fi
}

lock_ipc() {
  method="$1"
  ensure_hypr_env
  quickshell ipc --path "${DESKTOP_SHELL_QML}"/lock.qml call screenLock "$method"
}

lock_env() {
  export DESKTOP_SHELL_BACKEND="$desktop_shell_executable"
  export DESKTOP_SHELL_DEFAULT_WALLPAPER="$default_wallpaper"
  export WALLPAPER_PICKER_STATE_DIR="$wallpaper_state_dir"
}

lock_run() {
  lock_env
  ensure_hypr_env
  exec quickshell \
    --no-duplicate \
    --path "${DESKTOP_SHELL_QML}"/lock.qml
}

lock_prepare_keyboard() {
  ensure_hypr_env
  lock_keyboard_snapshot="$(keyboard_json 2>/dev/null || true)"
  lock_restore_keyboard="$(printf '%s\n' "$lock_keyboard_snapshot" | jq -r '.name // ""' 2>/dev/null || true)"
  lock_restore_index="$(printf '%s\n' "$lock_keyboard_snapshot" | jq -r '.index // 0' 2>/dev/null || printf '0\n')"
  case "$lock_restore_index" in
    "" | *[!0-9]*) lock_restore_index=0 ;;
  esac

  lock_keyboard_index="${DESKTOP_SHELL_LOCK_KEYBOARD_INDEX:-}"
  case "$lock_keyboard_index" in
    "") return 0 ;;
    *[!0-9]*) return 0 ;;
  esac

  if [ -n "$lock_restore_keyboard" ]; then
    keyboard_set_layout "$lock_restore_keyboard" "$lock_keyboard_index"
  fi
}

lock_start() {
  lock_prepare_keyboard
  systemd-run \
    --user \
    --collect \
    --unit desktop-lock \
    "--setenv=DESKTOP_LOCK_RESTORE_KEYBOARD=$lock_restore_keyboard" \
    "--setenv=DESKTOP_LOCK_RESTORE_INDEX=$lock_restore_index" \
    --quiet \
    "$desktop_shell_executable" lock-run >/dev/null
}

lock_screen() {
  method="${1:-lock}"
  case "$method" in
    lock | status | focus) ;;
    *) exit 2 ;;
  esac

  case "$method" in
    status)
      state="$(lock_ipc status 2>/dev/null || true)"
      if [ "$state" = true ]; then
        printf 'true\n'
      else
        printf 'false\n'
      fi
      ;;
    focus)
      lock_ipc focus >/dev/null 2>&1 || true
      ;;
    lock)
      state="$(lock_ipc status 2>/dev/null || true)"
      if [ "$state" = true ]; then
        lock_ipc focus >/dev/null 2>&1 || true
      else
        lock_start
      fi
      ;;
  esac
}
