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

launcher_state_json() {
  local clients active

  ensure_hypr_env
  clients="$(hyprctl clients -j)"
  active="$(hyprctl activewindow -j)"
  jq -e 'type == "array"' >/dev/null <<<"$clients"
  jq -e 'type == "object"' >/dev/null <<<"$active"
  jq -nc \
    --argjson clients "$clients" \
    --argjson active "$active" \
    '{clients: $clients, active: $active}'
}

launcher_apply_plan() {
  local plan_json="${1:-}"
  local active_address ordered_moves move address workspace command clients
  local moved launched

  if ! jq -e '
    type == "object"
    and (.moves | type == "array" and length <= 128)
    and (.launches | type == "array" and length <= 128)
    and all(.moves[];
      type == "object"
      and (.address | type == "string" and test("^0x[0-9A-Fa-f]+$"))
      and (.workspace | type == "number" and floor == . and . > 0))
    and all(.launches[];
      type == "object"
      and (.id | type == "string" and test("^[A-Za-z0-9_.+-]+[.]desktop$"))
      and (.workspace | type == "number" and floor == . and . > 0))
  ' >/dev/null <<<"$plan_json"; then
    printf 'desktop-shell: invalid launcher apply plan\n' >&2
    return 2
  fi

  ensure_hypr_env
  mkdir -p "${XDG_RUNTIME_DIR:?}/desktop-shell"
  exec 9>"$XDG_RUNTIME_DIR/desktop-shell/profile-apply.lock"
  flock -x 9

  active_address="$(hyprctl activewindow -j | jq -er '.address // ""')"
  ordered_moves="$(
    jq -c --arg active "$active_address" \
      '[.moves[] | select(.address != $active)] + [.moves[] | select(.address == $active)]' \
      <<<"$plan_json"
  )"

  while IFS= read -r move; do
    [ -n "$move" ] || continue
    address="$(jq -r '.address' <<<"$move")"
    workspace="$(jq -r '.workspace' <<<"$move")"
    command="hl.dsp.window.move({ workspace = $workspace, follow = false, window = \"address:$address\" })"
    hyprctl dispatch "$command" >/dev/null
  done < <(jq -c '.[]' <<<"$ordered_moves")

  clients="$(hyprctl clients -j)"
  if ! jq -e --argjson plan "$plan_json" '
    (map({key: .address, value: .workspace.id}) | from_entries) as $workspaces
    | all($plan.moves[]; $workspaces[.address] == .workspace)
  ' >/dev/null <<<"$clients"; then
    printf 'desktop-shell: profile window placement verification failed\n' >&2
    return 1
  fi

  while IFS= read -r move; do
    [ -n "$move" ] || continue
    address="$(jq -r '.id' <<<"$move")"
    workspace="$(jq -r '.workspace' <<<"$move")"
    launcher_record_launch "$address" || true
    launcher_launch_in_workspace "$address" "$workspace"
  done < <(jq -c '.launches[]' <<<"$plan_json")

  moved="$(jq '.moves | length' <<<"$plan_json")"
  launched="$(jq '.launches | length' <<<"$plan_json")"
  jq -nc --argjson moved "$moved" --argjson launched "$launched" \
    '{moved: $moved, launched: $launched}'
}
