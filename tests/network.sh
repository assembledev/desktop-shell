#!/usr/bin/env bash
set -euo pipefail
source_root="${1:?source root is required}"
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT
# shellcheck source=../src/backend/lib/network.sh
source "$source_root/src/backend/lib/network.sh"
export DESKTOP_SHELL_SYS_ROOT="$test_root/sys"
mkdir -p "$DESKTOP_SHELL_SYS_ROOT/class/net/wlan0/statistics" "$DESKTOP_SHELL_SYS_ROOT/class/net/eth0/statistics"
printf '1000\n' >"$DESKTOP_SHELL_SYS_ROOT/class/net/wlan0/statistics/rx_bytes"
printf '2000\n' >"$DESKTOP_SHELL_SYS_ROOT/class/net/wlan0/statistics/tx_bytes"
printf '1000\n' >"$DESKTOP_SHELL_SYS_ROOT/class/net/eth0/speed"
fixture_devices=$'wlan0:wifi:connected\neth0:ethernet:connected\nvpn0:tun:connected (externally)'
fixture_routes='[{"dev":"wlan0","metric":100},{"dev":"eth0","metric":200},{"dev":"vpn0","metric":0}]'
fixture_nm_failure=0
fixture_ping_status=0
nmcli() {
  [ "$fixture_nm_failure" -eq 0 ] || return 1
  if [[ "$*" == *' device status' ]]; then
    printf '%s\n' "$fixture_devices"
  elif [[ "$*" == *' device show '* ]]; then
    printf '%s\n' 'GENERAL.CONNECTION:Cafe: Lab' 'IP4.ADDRESS[1]:192.0.2.24/24' \
      'IP4.GATEWAY:192.0.2.1' 'IP4.DNS[1]:192.0.2.53' 'IP6.ADDRESS[1]:2001:db8::24/64' \
      'IP6.ADDRESS[2]:fe80::24/64' 'IP6.GATEWAY:fe80::1' 'IP6.DNS[1]:2001:db8::53'
  else
    return 2
  fi
}
ip() { if [ "$2" = -4 ]; then printf '%s\n' "$fixture_routes"; else printf '[]\n'; fi; }
iw() { printf 'freq: 5300.0\ntx bitrate: 866.7 MBit/s 80MHz\n'; }
ping() {
  [ "$*" = '-n -c 1 -W 1 -w 2 1.1.1.1' ] || return 2
  if [ "$fixture_ping_status" -eq 0 ]; then printf '64 bytes: time=12.34 ms\n'; fi
  return "$fixture_ping_status"
}
network_snapshot_json link | jq -e '.connected and .interface == "wlan0" and .type == "wifi" and .detailed == false and .rxBytes == null' >/dev/null
network_snapshot_json details | jq -e '
  .connection == "Cafe: Lab" and .ipv4 == ["192.0.2.24"] and .ipv6 == ["2001:db8::24"]
  and .gateway == "192.0.2.1" and .gateway6 == "fe80::1"
  and .dns == ["192.0.2.53", "2001:db8::53"] and .frequencyMHz == 5300 and .linkMbps == 866.7
  and .rxBytes == 1000 and .txBytes == 2000' >/dev/null
fixture_routes='[{"dev":"eth0","metric":10},{"dev":"wlan0","metric":100}]'
network_snapshot_json details | jq -e '.type == "ethernet" and .interface == "eth0" and .linkMbps == 1000 and .rxBytes == null' >/dev/null
fixture_routes='[]'
network_snapshot_json link | jq -e '.type == "ethernet"' >/dev/null
fixture_devices=$'vpn0:tun:connected (externally)\nwlan0:wifi:disconnected'
network_snapshot_json details | jq -e '.available and (.connected | not) and .interface == "" and (has("ipv4") | not)' >/dev/null
fixture_nm_failure=1
network_snapshot_json details | jq -e '(.available | not) and (.connected | not)' >/dev/null
network_ping_json | jq -e '.target == "1.1.1.1" and .state == "reachable" and .milliseconds == 12.34' >/dev/null
fixture_ping_status=1
network_ping_json | jq -e '.state == "timeout" and .milliseconds == null' >/dev/null
fixture_ping_status=2
network_ping_json | jq -e '.state == "unavailable" and .milliseconds == null' >/dev/null
