#!/usr/bin/env bash

system_status_json() {
  local system_path="${1:-/run/current-system}"
  local profiles="${2:-/nix/var/nix/profiles}"
  local running profile candidate specialisation state=test timestamp

  if ! running="$(readlink -e -- "$system_path")"; then
    printf '{"available":false}\n'
    return
  fi

  for profile in "$profiles"/system-*-link; do
    candidate="$(readlink -e -- "$profile")" || continue
    if [ "$candidate" = "$running" ]; then
      state=switch
      break
    fi
    for specialisation in "$candidate"/specialisation/*; do
      if [ "$(readlink -e -- "$specialisation" 2>/dev/null)" = "$running" ]; then
        state=switch
        break 2
      fi
    done
  done

  # Read the host's existing store metadata without opening the daemon or
  # recording a rebuild. Older Nix versions may leave the timestamp unavailable.
  timestamp="$(
    nix path-info --extra-experimental-features read-only-local-store \
      --store 'local?read-only=true' --json --json-format 1 "$running" 2>/dev/null |
      jq -er --arg path "$running" '.[$path].registrationTime // empty' 2>/dev/null
  )" || timestamp=null
  case "$timestamp" in
    '' | *[!0-9]*) timestamp=null ;;
  esac

  jq -n --arg state "$state" --argjson registrationTime "$timestamp" \
    '{available: true, state: $state, registrationTime: $registrationTime}'
}
