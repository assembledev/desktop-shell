#!/usr/bin/env bash

network_control_command() {
  local control_id="$1"
  local action="$2"
  local command_reader_pid
  local -a network_argv
  case "$control_id:$action" in
    *[!A-Za-z0-9_.:-]* | :* | *:) return 2 ;;
  esac

  # Validate the complete argv before emitting it; NUL preserves empty and
  # multiline arguments without interpreting their contents as shell code.
  mapfile -d '' -t network_argv < <(
    jq -j \
      --arg id "$control_id" \
      --arg key "${action}Command" '
        [.bar.networkControls[]? | select(.id == $id)]
        | if length == 1 then .[0][$key] else null end
        | if type != "array" then error("missing command")
          elif length == 0 then error("empty command")
          elif any(.[]; type != "string") then error("non-string argument")
          elif any(.[]; contains("\u0000")) then error("NUL in argument")
          elif .[0] == "" then error("empty executable")
          else . end
        | .[] + "\u0000"
      ' "$desktop_shell_config"
  )
  command_reader_pid=$!
  if ! wait "$command_reader_pid"; then
    printf 'desktop-shell: network control %s has invalid %s command\n' "$control_id" "$action" >&2
    return 2
  fi
  [ "${#network_argv[@]}" -gt 0 ] || return 2
  "${network_argv[@]}"
}
