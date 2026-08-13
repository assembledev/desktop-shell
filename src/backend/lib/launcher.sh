#!/usr/bin/env bash

launcher_history_file="$desktop_shell_state_dir/launcher-usage.json"

launcher_history_json() {
  if [ -f "$launcher_history_file" ] && jq -e 'type == "object"' "$launcher_history_file" >/dev/null 2>&1; then
    jq -c . "$launcher_history_file"
  else
    jq -nc '{}'
  fi
}

launcher_record_launch() {
  entry_id="${1:-}"
  [ -n "$entry_id" ] || return 2

  now="$(date +%s)"
  tmp_file="$(mktemp "$desktop_shell_state_dir/launcher-usage.XXXXXX")"

  if ! launcher_history_json |
    jq -c \
      --arg entryId "$entry_id" \
      --argjson now "$now" \
      '
        .[$entryId] = {
          launchCount: (
            ((.[$entryId].launchCount // 0) | if type == "number" then . else 0 end) + 1
          ),
          lastLaunch: $now
        }
      ' >"$tmp_file"; then
    rm -f "$tmp_file"
    return 1
  fi

  mv "$tmp_file" "$launcher_history_file"
}

launcher_entry_id_is_valid() {
  case "${1:-}" in
    *.desktop)
      case "$1" in
        *[!A-Za-z0-9_.+-]*) return 1 ;;
      esac
      ;;
    *) return 1 ;;
  esac
}

launcher_workspace_is_valid() {
  case "${1:-}" in
    "" | 0 | *[!0-9]* | 0*) return 1 ;;
  esac
}

launcher_window_address_is_valid() {
  case "${1:-}" in
    0x*[!0-9A-Fa-f]* | 0x) return 1 ;;
    0x*) ;;
    *) return 1 ;;
  esac
}

launcher_launch_in_workspace() {
  local entry_id="${1:-}"
  local workspace="${2:-}"
  local command_lua workspace_lua

  if ! launcher_entry_id_is_valid "$entry_id"; then
    printf 'desktop-shell: invalid desktop-entry ID: %s\n' "$entry_id" >&2
    return 2
  fi
  if ! launcher_workspace_is_valid "$workspace"; then
    printf 'desktop-shell: invalid workspace: %s\n' "$workspace" >&2
    return 2
  fi

  command_lua="$(printf 'uwsm app -- %s' "$entry_id" | jq -Rs .)"
  workspace_lua="$(printf '%s silent' "$workspace" | jq -Rs .)"
  ensure_hypr_env
  hyprctl eval \
    "hl.exec_cmd($command_lua, { workspace = $workspace_lua, focus_on_activate = false })" \
    >/dev/null
}

launcher_move_to_workspace() {
  local address="${1:-}"
  local workspace="${2:-}"
  local window_lua

  if ! launcher_window_address_is_valid "$address"; then
    printf 'desktop-shell: invalid window address: %s\n' "$address" >&2
    return 2
  fi
  if ! launcher_workspace_is_valid "$workspace"; then
    printf 'desktop-shell: invalid workspace: %s\n' "$workspace" >&2
    return 2
  fi

  window_lua="$(printf 'address:%s' "$address" | jq -Rs .)"
  ensure_hypr_env
  hyprctl dispatch \
    "hl.dsp.window.move({ workspace = $workspace, follow = false, window = $window_lua })" \
    >/dev/null
}
