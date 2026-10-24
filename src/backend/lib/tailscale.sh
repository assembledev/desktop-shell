#!/usr/bin/env bash

# LocalAPI only: no credentials, external API, cached netmap, or root helper.
tailscale_api() {
  curl --disable --noproxy '*' --silent --show-error --fail \
    --connect-timeout 1 --max-time 4 \
    --unix-socket "${DESKTOP_SHELL_TAILSCALE_SOCKET:-/var/run/tailscale/tailscaled.sock}" \
    "$@"
}

tailscale_status_json() {
  tailscale_api http://local-tailscaled.sock/localapi/v0/status
}

tailscale_snapshot_json() {
  local include_inbox="${1:-true}" status files='null' inbox_available=false
  if ! status="$(tailscale_status_json 2>/dev/null)" || ! jq -e 'type == "object" and (.BackendState | type == "string")' >/dev/null 2>&1 <<<"$status"; then
    printf '{"available":false,"connected":false,"state":"Unavailable","peers":[],"files":[],"inboxAvailable":false}\n'
    return
  fi
  if [ "$include_inbox" = true ] && files="$(tailscale_api http://local-tailscaled.sock/localapi/v0/files/ 2>/dev/null)" && jq -e 'type == "array" or . == null' >/dev/null <<<"$files"; then
    inbox_available=true
  else
    files='null'
  fi
  jq -nc --argjson status "$status" --argjson files "$files" --argjson inbox "$inbox_available" '
    def peer:
      {id: .ID, name: (if (.DNSName // "") != "" then (.DNSName | split(".")[0]) else .HostName end),
       hostname: (.HostName // ""), dnsName: ((.DNSName // "") | rtrimstr(".")), os: (.OS // ""),
       addresses: (.TailscaleIPs // []), tags: (.Tags // []), online: (.Online == true), lastSeen: (.LastSeen // ""),
       expired: (.Expired == true), canSend: (.TaildropTarget == 1),
       connection: (if .Online != true then "offline" elif .Active != true then "idle"
         elif (.PeerRelay // "") != "" then "peer-relay" elif (.CurAddr // "") != "" then "direct"
         elif (.Relay // "") != "" then "relay" else "unknown" end), relay: (.Relay // "")};
    ($status.BackendState == "Running") as $connected |
    {available: true, connected: $connected, state: $status.BackendState,
     self: ($status.Self | peer),
     peers: (if $connected then [$status.Peer[]? | select(.ShareeNode != true) | peer]
       | sort_by([if .online then 0 else 1 end, (.name | ascii_downcase), .id]) else [] end),
     files: [($files // [])[] | {name: .Name, size: .Size}], inboxAvailable: $inbox}
  '
}

# The model owns the waiting connection directly, so disabling it cancels curl
# rather than leaving a child behind. Zero seeds the inbox; 3600 awaits arrivals.
tailscale_inbox_json() {
  local wait_seconds="$1"
  case "$wait_seconds" in 0 | 3600) ;; *) return 2 ;; esac
  exec curl --disable --noproxy '*' --silent --show-error --fail \
    --connect-timeout 1 --max-time "$((wait_seconds + 5))" \
    --unix-socket "${DESKTOP_SHELL_TAILSCALE_SOCKET:-/var/run/tailscale/tailscaled.sock}" \
    "http://local-tailscaled.sock/localapi/v0/files/?waitsec=$wait_seconds"
}

tailscale_peer_json() {
  local id="$1"
  tailscale_status_json | jq -ce --arg id "$id" '
    select(.BackendState == "Running") | .Peer[]? | select(.ID == $id and .ShareeNode != true)
  '
}

tailscale_ping_json() {
  local peer ip response code=0
  peer="$(tailscale_peer_json "$1")" || return 1
  if ! jq -e '.Online == true' >/dev/null <<<"$peer"; then
    printf '{"state":"offline","milliseconds":null,"connection":"offline"}\n'
    return
  fi
  ip="$(jq -er '.TailscaleIPs[0]' <<<"$peer")" || return 1
  response="$(tailscale_api --max-time 3 --request POST --get --data-urlencode "ip=$ip" --data-urlencode type=disco http://local-tailscaled.sock/localapi/v0/ping 2>/dev/null)" || code=$?
  if [ "$code" -ne 0 ] || ! jq -e 'type == "object"' >/dev/null 2>&1 <<<"$response"; then
    jq -nc --argjson code "$code" '{state: (if $code == 28 then "timeout" else "unavailable" end), milliseconds:null, connection:"unknown"}'
    return
  fi
  jq -c '
    if (.Err // "") != "" or (.LatencySeconds | type) != "number" then
      {state:"timeout",milliseconds:null,connection:"unknown"}
    else {state:"reachable", milliseconds:(.LatencySeconds * 1000),
      connection:(if (.PeerRelay // "") != "" then "peer-relay" elif (.Endpoint // "") != "" then "direct"
        elif (.DERPRegionID // 0) != 0 then "relay" else "unknown" end), relay:(.DERPRegionCode // "")} end
  ' <<<"$response"
}

# One file per process lets the shell cancel the actual upload, not a wrapper.
# Eligibility is rechecked at send time, including changes since the panel opened.
tailscale_send_file() {
  local peer id="$1" file="$2" name
  case "$file" in /*) ;; *) file="$PWD/$file" ;; esac
  [ -f "$file" ] && [ -r "$file" ] || {
    printf 'Choose a readable regular file\n' >&2
    return 2
  }
  peer="$(tailscale_peer_json "$id")" || return 1
  jq -e '.TaildropTarget == 1' >/dev/null <<<"$peer" || {
    printf 'Device cannot receive files\n' >&2
    return 1
  }
  name="$(printf '%s' "${file##*/}" | jq -sRr '@uri')"
  id="$(printf '%s' "$id" | jq -sRr '@uri')"
  exec curl --disable --noproxy '*' --silent --show-error --fail \
    --connect-timeout 3 --max-time 3600 \
    --unix-socket "${DESKTOP_SHELL_TAILSCALE_SOCKET:-/var/run/tailscale/tailscaled.sock}" \
    --upload-file "$file" "http://local-tailscaled.sock/localapi/v0/file-put/$id/$name"
}

tailscale_file_info() (
  set -o pipefail
  local file size
  for file in "$@"; do
    [ -f "$file" ] && [ -r "$file" ] || return 2
    size="$(stat -Lc '%s' -- "$file")" || return 1
    jq -nc --arg path "$file" --arg name "${file##*/}" --argjson size "$size" '{path:$path,name:$name,size:$size}'
  done | jq -s .
)

# The chooser owns overwrite confirmation. Publish the complete file atomically,
# then acknowledge the inbox; failed downloads leave the destination untouched.
tailscale_receive_file() (
  local name="$1" target="$2" escaped temporary expected files removed=true
  case "$target" in /*) ;; *)
    printf 'Destination must be an absolute path\n' >&2
    return 2
    ;;
  esac
  files="$(tailscale_api http://local-tailscaled.sock/localapi/v0/files/)" || return 1
  expected="$(jq -er --arg name "$name" '.[]? | select(.Name == $name) | .Size' <<<"$files")" || return 1
  escaped="$(printf '%s' "$name" | jq -sRr '@uri')"
  temporary="$(mktemp -- "${target%/*}/.taildrop.XXXXXXXX")" || return 1
  trap 'rm -f -- "$temporary"' EXIT
  tailscale_api --max-time 3600 --output "$temporary" "http://local-tailscaled.sock/localapi/v0/files/$escaped" || return 1
  [ "$(stat -c '%s' -- "$temporary")" = "$expected" ] || {
    printf 'Incomplete download; file remains in inbox\n' >&2
    return 1
  }
  mv -fT -- "$temporary" "$target" || return 1
  tailscale_api --request DELETE "http://local-tailscaled.sock/localapi/v0/files/$escaped" >/dev/null || removed=false
  jq -nc --arg path "$target" --argjson removed "$removed" '{saved:true,path:$path,inboxRemoved:$removed}'
)

tailscale_command() {
  local action="${1:-status-json}" id file
  if [ "$#" -gt 0 ]; then shift; fi
  case "$action:$#" in
    status-json:0) tailscale_snapshot_json ;;
    peers-json:0) tailscale_snapshot_json false ;;
    inbox-json:1) tailscale_inbox_json "$1" ;;
    ping:1) tailscale_ping_json "$1" ;;
    file-info:*) [ "$#" -gt 0 ] && tailscale_file_info "$@" ;;
    send-file:2) tailscale_send_file "$1" "$2" ;;
    receive:2) tailscale_receive_file "$1" "$2" ;;
    send:*)
      [ "$#" -ge 2 ] || return 2
      id="$1"
      shift
      for file in "$@"; do
        (tailscale_send_file "$id" "$file") || return 1
        jq -nc --arg path "$file" '{sent:true,path:$path}'
      done
      ;;
    *) cli_usage_error tailscale ;;
  esac
}
