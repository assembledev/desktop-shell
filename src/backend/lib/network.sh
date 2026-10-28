#!/usr/bin/env bash

network_control_run_argv() {
  local provider="$1" key="$2" command_reader_pid
  local -a network_argv
  # The provider was validated as a complete mode before any command runs.
  # NUL preserves empty/multiline arguments without interpreting shell code.
  mapfile -d '' -t network_argv < <(jq -j --arg key "$key" '.[$key][] + "\u0000"' <<<"$provider")
  command_reader_pid=$!
  wait "$command_reader_pid" || return 2
  [ "${#network_argv[@]}" -gt 0 ] || return 2
  "${network_argv[@]}"
}

network_service_state() {
  local unit="$1" state command_status
  if state="$(timeout --signal=TERM --kill-after=0.2s 2s systemctl is-active -- "$unit" 2>&1)"; then
    :
  else
    command_status=$?
    case "$state" in
      inactive | failed | activating | deactivating) ;;
      *)
        printf 'desktop-shell: could not read %s state: %s\n' "$unit" "${state:-exit $command_status}" >&2
        return "$command_status"
        ;;
    esac
  fi
  printf '%s\n' "$state"
}

network_service_control() {
  local provider="$1" action="$2" unit label state key
  unit="$(jq -r '.unit' <<<"$provider")"
  label="$(jq -r '.label // .id' <<<"$provider")"
  state="$(network_service_state "$unit")" || return "$?"
  if [ "$action" = status ]; then
    jq -nc --arg state "$state" --arg label "$label" '
      {text: ($label + (if $state == "failed" then "!"
          elif $state == "activating" or $state == "deactivating" then "…" else "" end)),
       active: ($state == "active"), login: ($state == "failed"),
       tooltip: ($label + (if $state == "active" then " is active"
          elif $state == "inactive" then " is inactive"
          elif $state == "activating" then " is connecting"
          elif $state == "deactivating" then " is disconnecting"
          elif $state == "failed" then " failed; click to retry"
          else error("unsupported service state: " + $state) end))}
    '
    return
  fi
  case "$state" in
    active) key=stopCommand ;;
    inactive) key=startCommand ;;
    failed) key=retryCommand ;;
    activating | deactivating)
      printf 'desktop-shell: %s is already transitioning: %s\n' "$unit" "$state" >&2
      return 1
      ;;
    *)
      printf 'desktop-shell: unsupported %s state: %s\n' "$unit" "$state" >&2
      return 1
      ;;
  esac
  network_control_run_argv "$provider" "$key"
}

network_control_command() {
  local control_id="$1" action="$2" provider mode
  [[ "$control_id" =~ ^[A-Za-z0-9_.-]+$ ]] || return 2
  case "$action" in status | toggle) ;; *) return 2 ;; esac
  # Raw JSON and Home Manager configurations share the same complete modes.
  # Validate every argv before executing anything, including an apparent prefix.
  if ! provider="$(jq -ce --arg id "$control_id" '
    def empty_command: . == null or . == [];
    def argv:
      type == "array" and length > 0 and all(.[]; type == "string" and (contains("\u0000") | not)) and .[0] != "";
    [.bar.networkControls[]? | select(.id == $id)]
    | if length == 1 then .[0] else error("missing or duplicate provider") end
    | if (.statusCommand | argv) and (.toggleCommand | argv) and .unit == null
         and (.startCommand | empty_command) and (.stopCommand | empty_command) and (.retryCommand | empty_command)
      then . + {_mode: "command"}
      elif (.statusCommand | empty_command) and (.toggleCommand | empty_command) then
        if .id == "tailscale" and .unit == null
           and (.startCommand | empty_command) and (.stopCommand | empty_command) and (.retryCommand | empty_command)
        then . + {_mode: "tailscale"}
        elif (.unit | type == "string" and length > 0 and (contains("\u0000") | not))
           and (.startCommand | argv) and (.stopCommand | argv) and (.retryCommand | argv)
        then . + {_mode: "service"}
        else error("incomplete built-in provider") end
      else error("incomplete custom provider") end
  ' "$desktop_shell_config")"; then
    printf 'desktop-shell: network control %s has invalid provider configuration\n' "$control_id" >&2
    return 2
  fi
  mode="$(jq -r '._mode' <<<"$provider")"
  case "$mode" in
    command) network_control_run_argv "$provider" "${action}Command" ;;
    service) network_service_control "$provider" "$action" ;;
    tailscale)
      # Load the existing LocalAPI owner only for an explicitly selected provider.
      # shellcheck source=tailscale.sh
      source "${BASH_SOURCE[0]%/*}/tailscale.sh"
      tailscale_control_command "$action"
      ;;
  esac
}

# Choose a connected physical uplink from the main routing table. Policy-routed
# VPNs must not replace the Wi-Fi/Ethernet identity or its local addresses.
network_snapshot_json() {
  local mode="${1:-link}" devices candidates routes selected interface kind
  local fields='{}' properties link='' frequency='' speed='' rx='' tx='' sys_root
  case "$mode" in link | details) ;; *) return 2 ;; esac
  if ! devices="$(nmcli --wait 2 --terse --escape no --fields DEVICE,TYPE,STATE device status 2>/dev/null)"; then
    printf '{"available":false,"connected":false,"interface":"","type":""}\n'
    return
  fi
  candidates="$(jq -Rsc '
    [split("\n")[] | split(":")
      | select(length >= 3 and (.[1] == "wifi" or .[1] == "ethernet") and (.[2] | startswith("connected")))
      | {interface: .[0], type: .[1]}]
  ' <<<"$devices")"
  routes="$(ip -j -4 route show default 2>/dev/null)" || routes='[]'
  if [ "$(jq 'length' <<<"$routes")" -eq 0 ]; then
    routes="$(ip -j -6 route show default 2>/dev/null)" || routes='[]'
  fi
  selected="$(jq -nc --argjson devices "$candidates" --argjson routes "$routes" '
    $devices | sort_by(
      .interface as $interface |
      ([$routes[] | select(.dev == $interface) | (.metric // 0)] | min) as $metric |
      [if $metric == null then 1 else 0 end, ($metric // 0), (if .type == "ethernet" then 0 else 1 end), .interface]
    ) | first // null
  ')"
  if [ "$selected" = null ]; then
    printf '{"available":true,"connected":false,"interface":"","type":""}\n'
    return
  fi
  interface="$(jq -r '.interface' <<<"$selected")"
  kind="$(jq -r '.type' <<<"$selected")"
  if [ "$mode" = details ]; then
    # Split at the first colon only. IPv6 and connection names can contain
    # colons; --escape no keeps their values literal rather than backslashed.
    if ! properties="$(nmcli --wait 2 --terse --escape no --fields GENERAL.CONNECTION,IP4.ADDRESS,IP4.GATEWAY,IP4.DNS,IP6.ADDRESS,IP6.GATEWAY,IP6.DNS device show "$interface" 2>/dev/null)"; then
      printf '{"available":true,"connected":false,"interface":"","type":""}\n'
      return
    fi
    fields="$(jq -Rsc '
      [split("\n")[] | capture("^(?<key>[^:]+):(?<value>.*)$") | select(.value != "" and .value != "--")] as $fields |
      def values($prefix): [$fields[] | select(.key | startswith($prefix)) | .value];
      {connection: (values("GENERAL.CONNECTION") | first // ""),
       ipv4: (values("IP4.ADDRESS[") | map(split("/")[0])),
       ipv6: (values("IP6.ADDRESS[") | map(split("/")[0] | select(startswith("fe80:") | not))),
       gateway: (values("IP4.GATEWAY") | first // ""),
       gateway6: (values("IP6.GATEWAY") | first // ""),
       dns: (values("IP4.DNS[") + values("IP6.DNS["))}
    ' <<<"$properties")"
    if [ "$kind" = wifi ]; then
      link="$(iw dev "$interface" link 2>/dev/null)" || link=''
      frequency="$(awk '$1 == "freq:" {print $2; exit}' <<<"$link")"
      speed="$(awk '$1 == "tx" && $2 == "bitrate:" && $4 == "MBit/s" {print $3; exit}' <<<"$link")"
    fi
    sys_root="${DESKTOP_SHELL_SYS_ROOT:-/sys}"
    if [ "$kind" = ethernet ] && [ -r "$sys_root/class/net/$interface/speed" ]; then
      speed="$(cat "$sys_root/class/net/$interface/speed" 2>/dev/null)" || speed=''
    fi
    if [ -r "$sys_root/class/net/$interface/statistics/rx_bytes" ]; then
      read -r rx <"$sys_root/class/net/$interface/statistics/rx_bytes" || rx=''
      read -r tx <"$sys_root/class/net/$interface/statistics/tx_bytes" || tx=''
    fi
  fi
  jq -nc --argjson selected "$selected" --argjson fields "$fields" --arg mode "$mode" \
    --arg frequency "$frequency" --arg speed "$speed" --arg rx "$rx" --arg tx "$tx" '
    def positive: tonumber? | select(. > 0);
    def counter: tonumber? | select(. >= 0);
    $selected + $fields + {available: true, connected: true, detailed: ($mode == "details"),
      frequencyMHz: ($frequency | positive // null), linkMbps: ($speed | positive // null),
      rxBytes: ($rx | counter // null), txBytes: ($tx | counter // null)}
  '
}

network_ping_json() {
  local output status=0 milliseconds=''
  output="$(LC_ALL=C ping -n -c 1 -W 1 -w 2 1.1.1.1 2>/dev/null)" || status=$?
  if [ "$status" -eq 0 ]; then
    milliseconds="$(awk -F 'time[=<]' 'NF > 1 {split($2, value, " "); print value[1]; exit}' <<<"$output")"
  fi
  jq -nc --arg milliseconds "$milliseconds" --argjson status "$status" '
    {target: "1.1.1.1", milliseconds: ($milliseconds | tonumber? // null),
     state: (if $status == 1 then "timeout" elif $status == 0 and $milliseconds != "" then "reachable" else "unavailable" end)}
  '
}

# Query the current IPv4 egress through normal routing, including VPNs. The
# popover owns the lookup lifecycle; this helper does not cache or schedule it.
network_public_ip_json() {
  local address='' status=0
  address="$(curl --disable --fail --silent --proto '=https' --ipv4 --connect-timeout 2 --max-time 4 --retry 1 --retry-delay 1 --retry-max-time 8 --retry-connrefused --max-filesize 64 https://ip.me 2>/dev/null)" || status=$?
  if [ "$status" -ne 0 ]; then address=''; fi
  jq -nc --arg address "$address" --argjson status "$status" '
    ($address | gsub("^\\s+|\\s+$"; "")) as $ip |
    (if ($ip | test("^([0-9]{1,3}\\.){3}[0-9]{1,3}$")) then
      ($ip | split(".") | all(.[]; tonumber <= 255)) else false end) as $valid |
    {state: (if $valid then "ready" else "unavailable" end), address: (if $valid then $ip else "" end),
     error: (if $valid then null elif $status == 0 then "invalid-response"
       elif $status == 28 then "timeout" elif $status == 6 then "dns"
       elif $status == 60 then "tls" elif $status == 22 then "service" else "connection" end)}
  '
}
