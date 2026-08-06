#!/usr/bin/env bash

network_control_command() {
  control_id="$1"
  action="$2"
  case "$control_id:$action" in
    *[!A-Za-z0-9_.:-]* | :* | *:) return 2 ;;
  esac

  command_key="${action}Command"
  if ! jq -e \
    --arg id "$control_id" \
    --arg key "$command_key" \
    'any(.bar.networkControls[]?; .id == $id and (.[$key] | type == "array" and length > 0))' \
    "$desktop_shell_config" >/dev/null; then
    printf 'desktop-shell: network control %s has no %s command\n' "$control_id" "$action" >&2
    return 2
  fi

  mapfile -t network_argv < <(
    jq -r \
      --arg id "$control_id" \
      --arg key "$command_key" \
      '.bar.networkControls[] | select(.id == $id) | .[$key][]' \
      "$desktop_shell_config"
  )
  [ "${#network_argv[@]}" -gt 0 ] || return 2
  "${network_argv[@]}"
}
