#!/usr/bin/env bash

# Public help and semantic IPC commands. No config parsing or service startup.
cli_help() {
  case "${1:-}" in
    "")
      cat <<'HELP'
Usage: desktop-shell <command> [arguments]

Lifecycle: start [--foreground], stop, restart, status, logs [--follow], doctor
Surfaces: open, close, toggle, launcher, cheatsheet, pick, lock, clipboard, bar
Desktop: audio, wifi, media, dnd, notifications, profile, display, focus
Devices: brightness, volume, bluetooth, power, network-control
Inspection: config, metrics, system status-json, browser-tabs, ipc
Wallpaper: list-json, current, set <path>, preview <path>, apply
Navigation: alttab <next|prev|commit|cancel>, direction <l|r|u|d>

Use desktop-shell <command> --help or desktop-shell help <command>.
Use desktop-shell help-all for all command topics.
New state queries and actions print JSON. Actions never start the shell service.
HELP
      ;;
    audio)
      cat <<'HELP'
Usage: desktop-shell audio [status-json|devices-json|streams-json]
       desktop-shell audio volume <0..150> [target]
       desktop-shell audio mute <on|off|toggle> [target]
       desktop-shell audio default <output|input> <target>
Targets: output (default), input, exact node name, or current PipeWire node ID.
Volume is percent and preserves mute. Device/stream IDs are session-local.
Mutations wait up to 3 seconds for observed volume, mute or default-device state.
Changing a preferred default does not promise to move existing application streams.
Examples: audio volume 35; audio mute on input; audio default output alsa_output.example
HELP
      ;;
    wifi)
      cat <<'HELP'
Usage: desktop-shell wifi [status-json|networks-json|on|off|scan]
       desktop-shell wifi <connect|disconnect> <ssid>
Uses the same NetworkManager Wi-Fi adapter and model as the control center.
connect uses saved networks; authenticate new networks in wifi-page first.
scan requests discovery for 15 seconds, then stops unless the Wi-Fi page is open.
Actions return accepted requests, not completed connection/scan results.
Query status-json afterwards for connected, busy and SSID; networks-json lists cached results.
HELP
      ;;
    media)
      cat <<'HELP'
Usage: desktop-shell media [status-json|players-json]
       desktop-shell media <play|pause|toggle|stop|next|previous> [player]
Player defaults to the shell's active player; use its full MPRIS D-Bus name to target one.
Unsupported controls fail. Actions return accepted requests; query status-json for resulting playback.
Track metadata is returned only by explicit media queries.
HELP
      ;;
    dnd)
      printf '%s\n' 'Usage: desktop-shell dnd [status-json|on|off|toggle]' 'Reads or persists do-not-disturb through the notification owner. Prints {dnd,count}.'
      ;;
    notifications)
      printf '%s\n' 'Usage: desktop-shell notifications [status-json|list-json|clear]' '       desktop-shell notifications dismiss <id>' 'status-json returns DND and count. list-json explicitly reads notification text.' 'dismiss/clear reuse the control center history actions, including its existing clear undo window.'
      ;;
    profile)
      printf '%s\n' 'Usage: desktop-shell profile [list-json|status-json <id>|apply <id> [--wait]]' 'apply without --wait dispatches the configured profile as before.' '--wait checks fresh compositor snapshots until all matching applications are on their declared workspaces (30-second limit).' 'status-json reports counts, ready, applying, queued and the last dispatch result.'
      ;;
    brightness)
      printf '%s\n' 'Usage: desktop-shell brightness [capabilities-json|get|set <percent>|up|down|watch|backend|idle-dim|idle-restore]' 'Uses a kernel backlight or DDC/CI. capabilities-json reports support and write access.' 'idle-dim/idle-restore belong to the idle daemon.'
      ;;
    bluetooth)
      printf '%s\n' 'Usage: desktop-shell bluetooth [status-json|devices-json|on|off|session|session-close|discover]' '       desktop-shell bluetooth <pair|connect|disconnect|remove> <address>' 'pair also trusts the device. session opens temporary pairing visibility; session-close restores privacy.' 'discover is an interactive backend command owned by the control center.'
      ;;
    display)
      printf '%s\n' 'Usage: desktop-shell display [status-json|apply <json>|keep <token>|rollback <token>|restore|reset]' 'apply validates a display request and arms a 20-second rollback deadline.' 'Use the returned token with keep or rollback. status-json reports pending state and connected outputs.' 'restore applies a saved physical-display profile; reset removes it and reloads declarative monitor rules.'
      ;;
    clipboard)
      printf '%s\n' 'Usage: desktop-shell clipboard [open|close|toggle|refresh|list-json|copy <record>|delete <record> [id] [kind]|wipe]' 'list-json returns history previews and opaque base64 records; copy takes the record from that query.' 'Clipboard contents are private. store reads stdin and is owned by the capture watchers.'
      ;;
    volume)
      printf '%s\n' 'Usage: desktop-shell volume <up|down|mute>' 'Legacy output shortcuts: change volume by 2 percent, or toggle mute.' 'Use audio for explicit volume/mute settings, input devices and application streams.'
      ;;
    power)
      printf '%s\n' 'Usage: desktop-shell power [status-json|set <profile>]' 'Queries ACPI platform power profiles. set requires a configured privileged helper.'
      ;;
    network-control)
      printf '%s\n' 'Usage: desktop-shell network-control <status|toggle> <id>' 'Runs the configured provider command for a stable control ID; does not grant extra privileges.'
      ;;
    config | ipc | browser-tabs | metrics | system)
      printf '%s\n' 'Inspection commands:' '  config path | config show' '  ipc list | ipc call <target> <method> [arguments...]' '  browser-tabs state-path' '  metrics | system status-json' 'Raw IPC and browser-tabs activate are internal/debug interfaces; prefer named commands.'
      ;;
    start | stop | restart | status | logs | doctor)
      printf '%s\n' 'Lifecycle: start [--foreground], stop, restart, status, logs [--follow], doctor' 'status exits 3 while inactive. restart affects only desktop-shell.service.'
      ;;
    launcher | cheatsheet | lock | bar | focus | open | close | toggle | pick | wifi-page | bluetooth-page | audio-page | display-page | alttab | direction | lock-preview | wallpaper-close)
      printf '%s\n' 'Surfaces:' '  open | close | toggle; wifi-page | bluetooth-page | audio-page | display-page' '  launcher <open|focus|close|toggle>; cheatsheet <open|close|toggle>' '  clipboard <open|close|toggle>; pick; wallpaper-close' '  bar <show|hide|calendar>; focus <on|off|restore>; lock [lock|status|focus]' '  lock-preview <open|close|toggle>' '  alttab <next|prev|commit|cancel>; direction <l|r|u|d>' 'Named surface commands start the service when necessary; lock waits for compositor confirmation.'
      ;;
    list-json | current | set | preview | apply)
      printf '%s\n' 'Wallpaper: list-json | current | set <path> | preview <path> | apply' 'set applies and saves; preview is transient; apply restores the saved selection.'
      ;;
    *)
      printf 'desktop-shell: unknown help topic: %s\n' "$1" >&2
      return 2
      ;;
  esac
}

cli_help_all() {
  cli_help
  for topic in audio wifi media dnd notifications profile brightness bluetooth display clipboard volume power network-control config start launcher set; do
    printf '\n'
    cli_help "$topic"
  done
}

runtime_json() {
  local reply code
  ensure_hypr_env
  if reply="$(timeout --kill-after=1s 5s quickshell ipc --path "${DESKTOP_SHELL_QML}/shell.qml" call "$@" 2>/dev/null)"; then
    :
  else
    code="$?"
    printf 'desktop-shell: shell IPC unavailable or timed out (exit %s); start the matching shell package first\n' "$code" >&2
    return 3
  fi
  if ! jq -e 'type == "object" or type == "array"' >/dev/null 2>&1 <<<"$reply"; then
    printf 'desktop-shell: running shell does not provide this command or returned invalid JSON\n' >&2
    return 3
  fi
  if jq -e 'type == "object" and has("error")' >/dev/null <<<"$reply"; then
    jq -r '"desktop-shell: " + .error.code + ": " + .error.message' <<<"$reply" >&2
    return 1
  fi
  jq -c . <<<"$reply"
}

cli_usage_error() {
  cli_help "$1" >&2
  return 2
}

audio_snapshot() {
  local attempt state
  for ((attempt = 0; attempt < 30; attempt++)); do
    state="$(runtime_json audio status)" || return "$?"
    if jq -e '.ready == true' >/dev/null <<<"$state"; then
      printf '%s\n' "$state"
      return 0
    fi
    sleep 0.1
  done
  printf 'desktop-shell: PipeWire nodes did not become ready\n' >&2
  return 1
}

audio_command() {
  local action="$1" selector="$2" value="$3" request state attempt observed
  # Track nodes and wait for initial synchronization before issuing a write once.
  audio_snapshot >/dev/null || return "$?"
  request="$(runtime_json audio command "$action" "$selector" "$value")" || return "$?"
  for ((attempt = 0; attempt < 30; attempt++)); do
    state="$(runtime_json audio status)" || return "$?"
    if observed="$(jq -ce --arg action "$action" --argjson request "$request" '
      ([.outputs[], .inputs[], .streams[]] | map(select(.id == $request.target and .name == $request.name))[0]) as $node
      | if $node == null then empty
        elif $action == "volume" and (($node.volume - $request.volume) | fabs) <= 0.1 then $node
        elif $action == "mute" and $node.muted == $request.muted then $node
        elif $action == "default" and
          (if $request.direction == "output" then .defaultOutput.id else .defaultInput.id end) == $request.target then $node
        else empty end
    ' <<<"$state")"; then
      jq -nc --argjson node "$observed" '{applied:true,node:$node}'
      return 0
    fi
    sleep 0.1
  done
  printf 'desktop-shell: requested audio state was not observed; the request may still take effect\n' >&2
  return 1
}

runtime_command() {
  local domain="$1" action="${2:-status-json}" state value target
  shift
  case "$domain:$action" in
    audio:status-json | audio:devices-json | audio:streams-json)
      [ "$#" -le 1 ] || {
        cli_usage_error audio
        return 2
      }
      state="$(audio_snapshot)" || return "$?"
      case "$action" in
        devices-json) jq -c '{defaultOutput,defaultInput,outputs,inputs}' <<<"$state" ;;
        streams-json) jq -c '.streams' <<<"$state" ;;
        *) printf '%s\n' "$state" ;;
      esac
      ;;
    audio:volume)
      [ "$#" -ge 2 ] && [ "$#" -le 3 ] || {
        cli_usage_error audio
        return 2
      }
      value="$2"
      if [[ ! "$value" =~ ^[0-9]+([.][0-9]+)?$ ]] || ! jq -en --arg value "$value" '($value|tonumber) <= 150' >/dev/null; then
        cli_usage_error audio
        return 2
      fi
      audio_command volume "${3:-output}" "$value"
      ;;
    audio:mute)
      [ "$#" -ge 2 ] && [ "$#" -le 3 ] || {
        cli_usage_error audio
        return 2
      }
      case "$2" in on | off | toggle) ;; *)
        cli_usage_error audio
        return 2
        ;;
      esac
      audio_command mute "${3:-output}" "$2"
      ;;
    audio:default)
      [ "$#" -eq 3 ] && [ -n "$3" ] || {
        cli_usage_error audio
        return 2
      }
      case "$2" in output | input) ;; *)
        cli_usage_error audio
        return 2
        ;;
      esac
      audio_command default "$3" "$2"
      ;;
    wifi:status-json | wifi:networks-json | media:status-json | media:players-json | notifications:status-json)
      [ "$#" -le 1 ] || {
        cli_usage_error "$domain"
        return 2
      }
      state="$(runtime_json "$domain" status)" || return "$?"
      case "$action" in
        networks-json) jq -c '.networks' <<<"$state" ;;
        players-json) jq -c '.players' <<<"$state" ;;
        *) printf '%s\n' "$state" ;;
      esac
      ;;
    wifi:on | wifi:off | wifi:scan)
      [ "$#" -eq 1 ] || {
        cli_usage_error wifi
        return 2
      }
      runtime_json wifi command "$action" ""
      ;;
    wifi:connect | wifi:disconnect)
      [ "$#" -eq 2 ] && [ -n "$2" ] || {
        cli_usage_error wifi
        return 2
      }
      runtime_json wifi command "$action" "$2"
      ;;
    media:play | media:pause | media:toggle | media:stop | media:next | media:previous)
      [ "$#" -ge 1 ] && [ "$#" -le 2 ] || {
        cli_usage_error media
        return 2
      }
      runtime_json media command "$action" "${2:-active}"
      ;;
    dnd:status-json | dnd:on | dnd:off | dnd:toggle)
      [ "$#" -le 1 ] || {
        cli_usage_error dnd
        return 2
      }
      case "$action" in
        status-json) runtime_json notifications status ;;
        on | off)
          value=false
          [ "$action" = off ] || value=true
          runtime_json notifications setDnd "$value"
          ;;
        toggle)
          state="$(runtime_json notifications status)" || return "$?"
          value="$(jq -r '.dnd | not' <<<"$state")"
          runtime_json notifications setDnd "$value"
          ;;
      esac
      ;;
    notifications:list-json | notifications:clear)
      [ "$#" -eq 1 ] || {
        cli_usage_error notifications
        return 2
      }
      target=list
      [ "$action" = list-json ] || target=clear
      runtime_json notifications "$target"
      ;;
    notifications:dismiss)
      [ "$#" -eq 2 ] && [ -n "$2" ] || {
        cli_usage_error notifications
        return 2
      }
      runtime_json notifications dismiss "$2"
      ;;
    *)
      cli_usage_error "$domain"
      return 2
      ;;
  esac
}

profile_snapshot() {
  local profile="$1" state attempt
  runtime_json launcher profileStatus "$profile" true >/dev/null || return "$?"
  for ((attempt = 0; attempt < 20; attempt++)); do
    state="$(runtime_json launcher profileStatus "$profile" false)" || return "$?"
    if jq -e '.snapshotReady == true' >/dev/null <<<"$state"; then
      printf '%s\n' "$state"
      return 0
    fi
    sleep 0.05
  done
  printf 'desktop-shell: profile snapshot did not become ready\n' >&2
  return 1
}

profile_wait() {
  local profile="$1" started="$2" state deadline=$((SECONDS + 30))
  while [ "$SECONDS" -lt "$deadline" ]; do
    state="$(profile_snapshot "$profile")" || return "$?"
    if jq -e --argjson started "$started" '.lastResult.success == false and .lastResult.finishedAt >= $started' >/dev/null <<<"$state"; then
      printf 'desktop-shell: profile application failed\n' >&2
      return 1
    fi
    if jq -e '.converged and (.applying | not) and (.queued | not)' >/dev/null <<<"$state"; then
      printf '%s\n' "$state"
      return 0
    fi
    sleep 0.2
  done
  printf '%s\n' "$state"
  printf 'desktop-shell: profile did not converge within the verification deadline; applications may still be starting\n' >&2
  return 1
}
