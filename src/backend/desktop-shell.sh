#!/usr/bin/env bash

set -eu

desktop_shell_ipc_call() {
  target="$1"
  method="$2"
  shift 2

  if quickshell ipc --path "${DESKTOP_SHELL_QML}"/shell.qml call "$target" "$method" "$@" >/dev/null 2>&1; then
    return 0
  fi

  systemctl --user start desktop-shell.service
  attempt=0
  while [ "$attempt" -lt 20 ]; do
    sleep 0.1
    if quickshell ipc --path "${DESKTOP_SHELL_QML}"/shell.qml call "$target" "$method" "$@" >/dev/null 2>&1; then
      return 0
    fi
    attempt=$((attempt + 1))
  done

  printf 'desktop-shell: IPC target %s.%s did not become ready\n' "$target" "$method" >&2
  return 1
}

desktop_shell_wait_ready() {
  attempt=0
  while [ "$attempt" -lt 50 ]; do
    state="$(
      quickshell ipc --path "${DESKTOP_SHELL_QML}/shell.qml" call desktopShell ping 2>/dev/null || true
    )"
    if [ "$state" = true ]; then
      return 0
    fi
    sleep 0.1
    attempt=$((attempt + 1))
  done

  printf 'desktop-shell: QML IPC did not become ready\n' >&2
  return 1
}

desktop_shell_profile_wait_ready() {
  profile_id="$1"
  attempt=0
  service_started=0
  while [ "$attempt" -lt 50 ]; do
    if state="$(
      quickshell ipc --path "${DESKTOP_SHELL_QML}/shell.qml" call launcher profileReady "$profile_id" 2>/dev/null
    )"; then
      if [ "$state" = true ]; then
        return 0
      fi
    elif [ "$service_started" -eq 0 ]; then
      systemctl --user start desktop-shell.service
      service_started=1
    fi
    sleep 0.1
    attempt=$((attempt + 1))
  done

  printf 'desktop-shell: desktop entries did not become ready for profile: %s\n' "$profile_id" >&2
  return 1
}

# This is used by systemd as a startup readiness gate. Keep it independent of
# config parsing so a malformed user config cannot mask the actual QML result.
if [ "${1:-}" = wait-ready ]; then
  desktop_shell_wait_ready
  exit
fi

# Brightness changes are latency-sensitive continuous controls. The brightness
# backend is self-contained, so dispatch it without parsing the shell config or
# loading unrelated backend libraries. This is especially important for
# sequential gesture steps from Edgepad.
if [ "${1:-}" = brightness ]; then
  backend_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck source=lib/hypr-environment.sh
  source "$backend_dir/lib/hypr-environment.sh"
  # shellcheck source=lib/brightness.sh
  source "$backend_dir/lib/brightness.sh"

  case "${2:-get}" in
    backend)
      brightness_backend
      ;;
    capabilities-json)
      brightness_capabilities_json
      ;;
    get)
      brightness_get
      ;;
    watch)
      brightness_watch
      ;;
    set)
      brightness_set "${3:-50}"
      ;;
    up)
      brightness_adjust 5
      ;;
    down)
      brightness_adjust -5
      ;;
    idle-dim)
      brightness_idle_dim
      ;;
    idle-restore)
      brightness_idle_restore
      ;;
    *)
      printf 'usage: desktop-shell brightness [backend|capabilities-json|get|watch|set|up|down|idle-dim|idle-restore]\n' >&2
      exit 2
      ;;
  esac
  exit
fi

# Surface commands are latency-sensitive and need neither config parsing nor
# the backend libraries. Dispatch them before the heavyweight backend setup;
# desktop_shell_ipc_call still starts the service and retries when necessary.
case "${1:-}" in
  toggle | open | close)
    if [ "$#" -eq 1 ]; then
      desktop_shell_ipc_call controlCenter "$1"
      exit
    fi
    ;;
  wifi-page)
    if [ "$#" -eq 1 ]; then
      desktop_shell_ipc_call controlCenter wifiPage
      exit
    fi
    ;;
  bluetooth-page)
    if [ "$#" -eq 1 ]; then
      desktop_shell_ipc_call controlCenter bluetoothPage
      exit
    fi
    ;;
  display-page)
    if [ "$#" -eq 1 ]; then
      desktop_shell_ipc_call controlCenter displayPage
      exit
    fi
    ;;
  launcher)
    method="${2:-toggle}"
    if [ "$#" -le 2 ]; then
      case "$method" in
        open | close | toggle | focus)
          desktop_shell_ipc_call launcher "$method"
          exit
          ;;
      esac
    fi
    ;;
  cheatsheet | lock-preview)
    method="${2:-toggle}"
    if [ "$#" -le 2 ]; then
      case "$method" in
        open | close | toggle)
          desktop_shell_ipc_call "${1/lock-preview/lockPreview}" "$method"
          exit
          ;;
      esac
    fi
    ;;
  clipboard)
    method="${2:-toggle}"
    if [ "$#" -le 2 ]; then
      case "$method" in
        open | close | toggle)
          desktop_shell_ipc_call clipboardHistory "$method"
          exit
          ;;
      esac
    fi
    ;;
  pick)
    if [ "$#" -eq 1 ]; then
      desktop_shell_ipc_call wallpaperPicker pick
      exit
    fi
    ;;
  wallpaper-close)
    if [ "$#" -eq 1 ]; then
      desktop_shell_ipc_call wallpaperPicker close
      exit
    fi
    ;;
  bar)
    if [ "$#" -eq 2 ]; then
      case "${2:-}" in
        calendar)
          desktop_shell_ipc_call calendar toggle
          exit
          ;;
        show)
          desktop_shell_ipc_call desktopBar reveal
          exit
          ;;
        hide)
          desktop_shell_ipc_call desktopBar conceal
          exit
          ;;
      esac
    fi
    ;;
  ipc)
    case "${2:-}" in
      list)
        if [ "$#" -eq 2 ]; then
          exec quickshell ipc --path "${DESKTOP_SHELL_QML}"/shell.qml show
        fi
        ;;
      call)
        if [ "$#" -ge 4 ]; then
          target="$3"
          method="$4"
          shift 4
          exec quickshell ipc --path "${DESKTOP_SHELL_QML}"/shell.qml call "$target" "$method" "$@"
        fi
        ;;
    esac
    ;;
esac

# Alt-Tab is a latency-sensitive IPC path and does not consume shell config.
# Try it before loading the full backend; fall through on open failures so the
# regular service-start retry still applies.
if [ "${1:-}" = alttab ] && [ -n "${DESKTOP_SHELL_QML:-}" ] && command -v quickshell >/dev/null 2>&1; then
  action="${2:-next}"
  case "$action" in
    next | prev)
      if quickshell ipc --path "${DESKTOP_SHELL_QML}/shell.qml" call windowSwitcher alttab "$action" >/dev/null 2>&1; then
        exit 0
      fi
      ;;
    commit | cancel)
      quickshell ipc --path "${DESKTOP_SHELL_QML}/shell.qml" call windowSwitcher "$action" >/dev/null 2>&1 || true
      exit 0
      ;;
    *) exit 2 ;;
  esac
fi

backend_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$backend_dir/lib/common.sh"
# shellcheck source=lib/wallpaper.sh
source "$backend_dir/lib/wallpaper.sh"
# shellcheck source=lib/clipboard.sh
source "$backend_dir/lib/clipboard.sh"
# shellcheck source=lib/network.sh
source "$backend_dir/lib/network.sh"
# shellcheck source=lib/bluetooth.sh
source "$backend_dir/lib/bluetooth.sh"
# shellcheck source=lib/metrics.sh
source "$backend_dir/lib/metrics.sh"
# shellcheck source=lib/session.sh
source "$backend_dir/lib/session.sh"
# shellcheck source=lib/display.sh
source "$backend_dir/lib/display.sh"

print_help() {
  cat <<'EOF'
Usage: desktop-shell <command> [arguments]

Lifecycle:
  start [--foreground]  Start the user service, or run in the foreground
  stop                  Stop the user service
  restart               Restart the user service
  status                Show user-service status
  logs [--follow]       Show user-service logs
  doctor                Check configuration and runtime dependencies

Shell surfaces:
  open | close | toggle
  launcher <open|focus|close|toggle>
  profile apply <id>    Reconcile a configured application layout
  alttab <next|prev|commit|cancel>
  direction <l|r|u|d>
  cheatsheet <open|close|toggle>
  pick
  lock [lock|status|focus]
  clipboard <open|close|toggle>

Inspection:
  config path | config show
  ipc list | ipc call <target> <method> [arguments...]

Run `desktop-shell help-all` for backend and integration commands.
EOF
}

print_help_all() {
  print_help
  cat <<'EOF'

Integration and backend commands:
  browser-tabs, lock-preview, lock-keyboard, apply, current, list-json,
  preview, set, notification-status, bluetooth, brightness, volume, power,
  display, focus, profile, bar, network-control, cursor, hypr, metrics, sound, run,
  lock-run
EOF
}

service_status() {
  if systemctl --user --quiet is-active desktop-shell.service; then
    printf 'desktop-shell.service: active\n'
    return 0
  fi

  state="$(systemctl --user is-active desktop-shell.service 2>/dev/null || true)"
  printf 'desktop-shell.service: %s\n' "${state:-unknown}"
  return 3
}

doctor() {
  failures=0
  printf 'config: %s\n' "$desktop_shell_config"
  jq -e 'type == "object"' "$desktop_shell_config" >/dev/null || failures=$((failures + 1))

  for command in quickshell hyprctl jq systemctl; do
    if command -v "$command" >/dev/null 2>&1; then
      printf '%s: ok\n' "$command"
    else
      printf '%s: missing\n' "$command"
      failures=$((failures + 1))
    fi
  done

  ensure_hypr_env
  if hyprctl version >/dev/null 2>&1; then
    printf 'hyprland: reachable\n'
  else
    printf 'hyprland: not reachable\n'
    failures=$((failures + 1))
  fi

  if systemctl --user --quiet is-active desktop-shell.service; then
    printf 'service: active\n'
  else
    printf 'service: inactive\n'
  fi

  [ "$failures" -eq 0 ]
}

case "${1:-help}" in
  help | -h | --help)
    print_help
    ;;
  help-all)
    print_help_all
    ;;
  config)
    case "${2:-path}" in
      path)
        printf '%s\n' "$desktop_shell_config"
        ;;
      show)
        jq . "$desktop_shell_config"
        ;;
      *)
        printf 'usage: desktop-shell config [path|show]\n' >&2
        exit 2
        ;;
    esac
    ;;
  doctor)
    doctor
    ;;
  stop)
    systemctl --user stop desktop-shell.service
    ;;
  restart)
    systemctl --user restart desktop-shell.service
    ;;
  status)
    service_status
    ;;
  logs)
    case "${2:-}" in
      "") exec journalctl --user-unit desktop-shell.service --no-pager -n 200 ;;
      --follow | -f) exec journalctl --user-unit desktop-shell.service --follow ;;
      *)
        printf 'usage: desktop-shell logs [--follow]\n' >&2
        exit 2
        ;;
    esac
    ;;
  ipc)
    case "${2:-}" in
      list)
        exec quickshell ipc --path "${DESKTOP_SHELL_QML}"/shell.qml show
        ;;
      call)
        [ "$#" -ge 4 ] || {
          printf 'usage: desktop-shell ipc call <target> <method> [arguments...]\n' >&2
          exit 2
        }
        target="$3"
        method="$4"
        shift 4
        exec quickshell ipc --path "${DESKTOP_SHELL_QML}"/shell.qml call "$target" "$method" "$@"
        ;;
      *)
        printf 'usage: desktop-shell ipc [list|call]\n' >&2
        exit 2
        ;;
    esac
    ;;
  run)
    export CONTROL_CENTER_BACKEND="$desktop_shell_executable"
    export WALLPAPER_PICKER_BACKEND="$desktop_shell_executable"
    export DESKTOP_SHELL_BACKEND="$desktop_shell_executable"
    export DESKTOP_SHELL_DEFAULT_WALLPAPER="$default_wallpaper"
    export WALLPAPER_PICKER_STATE_DIR="$wallpaper_state_dir"
    export CONTROL_CENTER_STATE_DIR="$state_dir"
    export DESKTOP_SHELL_PREFERENCES_DIR="$preferences_state_dir"
    exec quickshell \
      --log-rules 'quickshell.hyprland.ipc.events=false;quickshell.wayland.toplevelManagement=false' \
      --path "${DESKTOP_SHELL_QML}"/shell.qml
    ;;
  lock-run)
    lock_run
    ;;
  start)
    case "${2:-}" in
      "") systemctl --user start desktop-shell.service ;;
      --foreground) exec "$desktop_shell_executable" run ;;
      *)
        printf 'usage: desktop-shell start [--foreground]\n' >&2
        exit 2
        ;;
    esac
    ;;
  toggle | open | close)
    desktop_shell_ipc_call controlCenter "$1"
    ;;
  wifi-page)
    desktop_shell_ipc_call controlCenter wifiPage
    ;;
  bluetooth-page)
    desktop_shell_ipc_call controlCenter bluetoothPage
    ;;
  display-page)
    desktop_shell_ipc_call controlCenter displayPage
    ;;
  launcher)
    method="${2:-toggle}"
    case "$method" in
      open | close | toggle | focus) ;;
      *) exit 2 ;;
    esac
    desktop_shell_ipc_call launcher "$method"
    ;;
  profile)
    action="${2:-list-json}"
    case "$action" in
      apply)
        profile_id="${3:-}"
        [ "$#" -eq 3 ] || exit 2
        if ! jq -e --arg profile "$profile_id" \
          '.launcher.profiles[$profile].applications | type == "array" and length > 0' \
          "$desktop_shell_config" >/dev/null; then
          printf 'desktop-shell: unknown launch profile: %s\n' "$profile_id" >&2
          exit 2
        fi
        desktop_shell_profile_wait_ready "$profile_id"
        desktop_shell_ipc_call launcher applyProfile "$profile_id"
        ;;
      list-json)
        [ "$#" -le 2 ] || exit 2
        jq -c '.launcher.profiles // {}' "$desktop_shell_config"
        ;;
      *)
        printf 'usage: desktop-shell profile [apply <id>|list-json]\n' >&2
        exit 2
        ;;
    esac
    ;;
  browser-tabs)
    case "${2:-}" in
      activate)
        [ "$#" -eq 5 ] || exit 2
        exec "$DESKTOP_SHELL_BROWSER_BRIDGE" activate "$3" "$4" "$5"
        ;;
      state-path)
        [ "$#" -eq 2 ] || exit 2
        printf '%s/desktop-shell/browser-tabs.json\n' "${XDG_RUNTIME_DIR:?}"
        ;;
      *)
        exit 2
        ;;
    esac
    ;;
  alttab)
    action="${2:-next}"
    case "$action" in
      next | prev)
        method="alttab"
        args="$action"
        ;;
      commit)
        method="commit"
        args=""
        ;;
      cancel)
        method="cancel"
        args=""
        ;;
      *)
        exit 2
        ;;
    esac
    if [ -n "$args" ]; then
      desktop_shell_ipc_call windowSwitcher "$method" "$args"
    else
      quickshell ipc --path "${DESKTOP_SHELL_QML}"/shell.qml call windowSwitcher "$method" >/dev/null 2>&1 || true
    fi
    ;;
  direction)
    direction="${2:-}"
    case "$direction" in
      l | r | u | d) ;;
      *) exit 2 ;;
    esac
    if ! quickshell ipc --path "${DESKTOP_SHELL_QML}"/shell.qml call windowSwitcher direction "$direction" >/dev/null 2>&1; then
      ensure_hypr_env
      hyprctl dispatch "hl.dsp.focus({ direction = \"$direction\" })" >/dev/null
    fi
    ;;
  cheatsheet)
    method="${2:-toggle}"
    case "$method" in
      open | close | toggle) ;;
      *) exit 2 ;;
    esac
    desktop_shell_ipc_call cheatsheet "$method"
    ;;
  pick)
    desktop_shell_ipc_call wallpaperPicker pick
    ;;
  wallpaper-close)
    quickshell ipc --path "${DESKTOP_SHELL_QML}"/shell.qml call wallpaperPicker close >/dev/null 2>&1 || true
    ;;
  lock)
    lock_screen "${2:-lock}"
    ;;
  lock-keyboard)
    case "${2:-}" in
      set)
        keyboard_set_layout "${3:-}" "${4:-}"
        ;;
      *)
        exit 2
        ;;
    esac
    ;;
  lock-preview)
    method="${2:-toggle}"
    case "$method" in
      open | close | toggle) ;;
      *) exit 2 ;;
    esac
    desktop_shell_ipc_call lockPreview "$method"
    ;;
  clipboard)
    case "${2:-open}" in
      open | close | toggle)
        clipboard_ipc "${2:-open}"
        ;;
      refresh)
        clipboard_refresh
        ;;
      list-json)
        clipboard_list_json
        ;;
      copy)
        clipboard_copy "${3:-}"
        ;;
      delete)
        clipboard_delete "${3:-}" "${4:-}" "${5:-}"
        ;;
      preview)
        clipboard_preview "${3:-}" "${4:-}" "${5:-}"
        ;;
      wipe)
        cliphist wipe
        find "$clipboard_preview_dir" -mindepth 1 -maxdepth 1 -delete
        ;;
      *)
        exit 2
        ;;
    esac
    ;;
  apply)
    current="$(read_current_wallpaper)"
    apply_wallpaper "$current"
    ;;
  current)
    read_current_wallpaper
    ;;
  list-json)
    list_wallpapers_json
    ;;
  preview)
    [ "$#" -eq 2 ] || exit 2
    preview_wallpaper "$2"
    ;;
  set)
    [ "$#" -eq 2 ] || exit 2
    apply_wallpaper "$2"
    ;;
  notification-status)
    dnd=0
    [ -f "$preferences_state_dir/dnd" ] && dnd="$(cat "$preferences_state_dir/dnd")"
    count=0
    [ -f "$state_dir/count" ] && count="$(cat "$state_dir/count")"
    if [ "$dnd" = 1 ] && [ "$count" -gt 0 ] 2>/dev/null; then
      icon=""
      class="dnd-unread"
    elif [ "$dnd" = 1 ]; then
      icon=""
      class="dnd"
    elif [ "$count" -gt 0 ] 2>/dev/null; then
      icon=""
      class="unread"
    else
      icon=""
      class="normal"
    fi
    jq -nc --arg text "$icon" --arg class "$class" --arg tooltip "Control center" \
      '{text: $text, class: $class, tooltip: $tooltip}'
    ;;
  bluetooth)
    case "${2:-status-json}" in
      status-json)
        bluetooth_status_json
        ;;
      devices-json)
        bluetooth_devices_json
        ;;
      on)
        bluetoothctl power on
        bluetooth_private_mode
        ;;
      off)
        bluetooth_private_mode
        bluetoothctl power off
        ;;
      session)
        bluetooth_pairing_session
        ;;
      session-close)
        bluetooth_private_mode
        ;;
      discover)
        # Kept interactive so the owning QML process can stop discovery through
        # the same D-Bus client before asking bluetoothctl to exit.
        exec bluetoothctl
        ;;
      pair)
        address="${3:-}"
        bluetooth_require_address "$address"
        bluetoothctl pair "$address"
        bluetoothctl trust "$address"
        bluetoothctl connect "$address" >/dev/null 2>&1 || true
        ;;
      connect | disconnect | remove)
        action="$2"
        address="${3:-}"
        bluetooth_require_address "$address"
        bluetoothctl "$action" "$address"
        ;;
      *)
        exit 2
        ;;
    esac
    ;;
  display)
    case "${2:-status-json}" in
      status-json)
        [ "$#" -le 2 ] || exit 2
        display_status_json
        ;;
      apply)
        [ "$#" -eq 3 ] || exit 2
        display_apply_request "$3"
        ;;
      keep | rollback)
        [ "$#" -eq 3 ] || exit 2
        "display_$2" "$3"
        ;;
      restore)
        [ "$#" -eq 2 ] || exit 2
        display_restore_profile
        ;;
      reset)
        [ "$#" -eq 2 ] || exit 2
        display_reset
        ;;
      *)
        printf 'usage: desktop-shell display [status-json|apply <json>|keep <token>|rollback <token>|restore|reset]\n' >&2
        exit 2
        ;;
    esac
    ;;
  volume)
    case "${2:-}" in
      up)
        pamixer -i 2
        ;;
      down)
        pamixer -d 2
        ;;
      mute)
        pamixer -t
        ;;
      *)
        printf 'usage: desktop-shell volume [up|down|mute]\n' >&2
        exit 2
        ;;
    esac
    ;;
  power)
    case "${2:-status-json}" in
      status-json)
        power_status_json
        ;;
      set)
        profile="${3:-}"
        power_set_profile "$profile"
        ;;
      *)
        printf 'usage: desktop-shell power [status-json|set <profile>]\n' >&2
        exit 2
        ;;
    esac
    ;;
  focus)
    case "${2:-restore}" in
      on)
        write_preference focus 1
        bar_hide
        ;;
      off)
        write_preference focus 0
        bar_show
        ;;
      restore)
        focus_restore
        ;;
    esac
    ;;
  bar)
    case "${2:-status}" in
      show)
        bar_show
        ;;
      hide)
        bar_hide
        ;;
      restore)
        focus_restore
        ;;
      battery-json)
        battery_json
        ;;
      keyboard-json)
        keyboard_json
        ;;
      calendar)
        calendar_popup
        ;;
      session)
        session_action "${3:-}"
        ;;
      *)
        printf 'usage: desktop-shell bar [show|hide|restore|battery-json|keyboard-json|calendar|session]\n' >&2
        exit 2
        ;;
    esac
    ;;
  network-control)
    case "${2:-}" in
      status | toggle)
        [ "$#" -eq 3 ] || exit 2
        network_control_command "$3" "$2"
        ;;
      *)
        printf 'usage: desktop-shell network-control [status|toggle] <id>\n' >&2
        exit 2
        ;;
    esac
    ;;
  cursor)
    case "${2:-near-top}" in
      near-top)
        ensure_hypr_env
        y="$(hyprctl cursorpos -j 2>/dev/null | jq -r '.y // 9999' || printf 9999)"
        if [ "$y" -le 45 ] 2>/dev/null; then
          printf 'yes\n'
        else
          printf 'no\n'
        fi
        ;;
    esac
    ;;
  metrics)
    metrics_json
    ;;
  sound)
    if [ "${2:-}" = notification ]; then
      pw-play "${DESKTOP_SHELL_NOTIFICATION_SOUND}" >/dev/null 2>&1 || true
    fi
    ;;
  *)
    printf 'desktop-shell: unknown command: %s\n' "${1:-}" >&2
    printf '%s\n' 'Run desktop-shell help for usage.' >&2
    exit 2
    ;;
esac
