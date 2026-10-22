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
  local address=''
  address="$(curl --disable --fail --silent --proto '=https' --ipv4 --connect-timeout 2 --max-time 4 --max-filesize 64 https://ip.me 2>/dev/null)" || address=''
  jq -nc --arg address "$address" '
    ($address | gsub("^\\s+|\\s+$"; "")) as $ip |
    (if ($ip | test("^([0-9]{1,3}\\.){3}[0-9]{1,3}$")) then
      ($ip | split(".") | all(.[]; tonumber <= 255)) else false end) as $valid |
    {state: (if $valid then "ready" else "unavailable" end), address: (if $valid then $ip else "" end)}
  '
}
