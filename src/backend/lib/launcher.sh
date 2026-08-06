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
