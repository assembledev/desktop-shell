#!/usr/bin/env bash
set -euo pipefail
source_root="${1:?source root required}"
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT
# shellcheck source=../src/backend/lib/tailscale.sh
source "$source_root/src/backend/lib/tailscale.sh"
cat >"$test_root/status" <<'JSON'
{"BackendState":"Running","Self":{"ID":"self","HostName":"local","Online":true,"TailscaleIPs":["100.64.0.1"]},"Peer":{
 "a":{"ID":"eligible","DNSName":"desktop.test.invalid.","HostName":"desktop","Online":true,"Active":true,"TaildropTarget":1,"CurAddr":"192.0.2.1:1234","TailscaleIPs":["100.64.0.2"],"OS":"linux"},
 "b":{"ID":"tagged","HostName":"server","Online":true,"Active":false,"TaildropTarget":9,"Tags":["tag:server","tag:backup"],"Relay":"abc","TailscaleIPs":["100.64.0.3"]},
 "c":{"ID":"offline","HostName":"phone","Online":false,"Active":true,"TaildropTarget":5,"CurAddr":"192.0.2.3:1234","TailscaleIPs":["100.64.0.4"]},
 "d":{"ID":"shared","HostName":"shared","Online":true,"ShareeNode":true},
 "e":{"ID":"peer-relay","HostName":"relay-peer","Online":true,"Active":true,"TaildropTarget":7,"PeerRelay":"192.0.2.2:12:vni:1","Relay":"abc"}
}}
JSON
printf 'null' >"$test_root/files"
printf '{"Err":"","LatencySeconds":0.012,"DERPRegionID":5,"DERPRegionCode":"abc"}' >"$test_root/ping"
printf 'test file' >"$test_root/source"
# Exercise the production serialization and file lifecycle against a fake LocalAPI.
tailscale_api() {
  local url="${*: -1}" output='' previous=''
  for argument in "$@"; do
    if [ "$previous" = --output ]; then output="$argument"; fi
    previous="$argument"
  done
  case "$url" in
    */status) cat "$test_root/status" ;;
    */files/)
      touch "$test_root/inbox-called"
      cat "$test_root/files"
      ;;
    */ping) cat "$test_root/ping" ;;
    */files/*)
      if [[ " $* " == *' DELETE '* ]]; then touch "$test_root/deleted"; else cp "$test_root/source" "$output"; fi
      ;;
    *) return 1 ;;
  esac
}
tailscale_snapshot_json | jq -e '.connected and (.peers|length == 4) and (.files|length == 0) and .inboxAvailable and ([.peers[] | select(.canSend)]|length == 1) and (.peers[] | select(.id == "tagged").connection == "idle") and (.peers[] | select(.id == "offline").connection == "offline") and (.peers[] | select(.id == "peer-relay").connection == "peer-relay")' >/dev/null
tailscale_snapshot_json | jq -e '(.peers[] | select(.id == "tagged").tags) == ["tag:server","tag:backup"] and (.peers[] | select(.id == "eligible").tags) == []' >/dev/null
rm "$test_root/inbox-called"
tailscale_snapshot_json false | jq -e '.available and (.inboxAvailable | not)' >/dev/null
test ! -e "$test_root/inbox-called"
tailscale_ping_json eligible | jq -e '.state == "reachable" and .connection == "relay" and .milliseconds == 12' >/dev/null
printf '{"Err":"","LatencySeconds":0.001,"Endpoint":"192.0.2.1:12","PeerRelay":"192.0.2.2:12:vni:1"}' >"$test_root/ping"
tailscale_ping_json eligible | jq -e '.connection == "peer-relay"' >/dev/null
printf '{"Err":"timeout"}' >"$test_root/ping"
tailscale_ping_json eligible | jq -e '.state == "timeout" and .connection == "unknown" and .milliseconds == null' >/dev/null
tailscale_ping_json offline | jq -e '.state == "offline"' >/dev/null
if tailscale_ping_json missing >/dev/null 2>&1; then exit 1; fi
printf '[{"Name":"../odd name #.txt","Size":9}]' >"$test_root/files"
tailscale_snapshot_json | jq -e '.files[0].name == "../odd name #.txt"' >/dev/null
# The untrusted inbox name is URL-encoded, never used as a destination path.
tailscale_receive_file '../odd name #.txt' "$test_root/saved" | jq -e '.saved and .inboxRemoved' >/dev/null
cmp "$test_root/source" "$test_root/saved"
test -f "$test_root/deleted"
rm "$test_root/deleted"
# Save dialogs may create the selected file before returning its path.
touch "$test_root/placeholder"
tailscale_receive_file '../odd name #.txt' "$test_root/placeholder" | jq -e '.saved and .inboxRemoved' >/dev/null
cmp "$test_root/source" "$test_root/placeholder"
test -f "$test_root/deleted"
rm "$test_root/deleted"
# Overwrite confirmation belongs to the chooser; the backend honors its path.
printf 'previous contents' >"$test_root/saved"
tailscale_receive_file '../odd name #.txt' "$test_root/saved" | jq -e '.saved and .inboxRemoved' >/dev/null
cmp "$test_root/source" "$test_root/saved"
test -f "$test_root/deleted"
rm "$test_root/deleted"
printf '[{"Name":"wrong-size","Size":100}]' >"$test_root/files"
if tailscale_receive_file wrong-size "$test_root/incomplete" >/dev/null 2>&1; then exit 1; fi
test ! -e "$test_root/incomplete"
test ! -e "$test_root/deleted"
# Failed downloads must preserve an already selected destination and the inbox.
printf 'previous contents' >"$test_root/saved"
if tailscale_receive_file wrong-size "$test_root/saved" >/dev/null 2>&1; then exit 1; fi
test "$(cat "$test_root/saved")" = 'previous contents'
test ! -e "$test_root/deleted"
test "$(find "$test_root" -name '.taildrop.*' | wc -l)" -eq 0
tailscale_file_info "$test_root/source" | jq -e '.[0].size == 9' >/dev/null
if tailscale_file_info "$test_root/source" "$test_root/missing" >/dev/null 2>&1; then exit 1; fi
# Send executes curl directly only after fresh eligibility. Capture its argv.
mkdir "$test_root/bin"
printf '#!%s\n' "$(command -v bash)" >"$test_root/bin/curl"
cat >>"$test_root/bin/curl" <<'SH'
printf '%s\n' "$@" >"$SEND_ARGUMENTS"
SH
chmod +x "$test_root/bin/curl"
export SEND_ARGUMENTS="$test_root/send-argv"
export PATH="$test_root/bin:$PATH"
strange="$test_root/line
name #.txt"
cp "$test_root/source" "$strange"
(tailscale_send_file eligible "$strange")
test -f "$SEND_ARGUMENTS"
[[ "$(tail -n 1 "$SEND_ARGUMENTS")" == *'/file-put/eligible/line%0Aname%20%23.txt' ]]
rm "$SEND_ARGUMENTS"
if (tailscale_send_file tagged "$test_root/source") >/dev/null 2>&1; then exit 1; fi
test ! -e "$SEND_ARGUMENTS"
(tailscale_inbox_json 3600)
mapfile -t inbox_arguments <"$SEND_ARGUMENTS"
test "${inbox_arguments[9]}" = 3605
test "${inbox_arguments[12]}" = 'http://local-tailscaled.sock/localapi/v0/files/?waitsec=3600'
rm "$SEND_ARGUMENTS"
if (tailscale_inbox_json -1) >/dev/null 2>&1; then exit 1; fi
if (tailscale_inbox_json 1) >/dev/null 2>&1; then exit 1; fi
test ! -e "$SEND_ARGUMENTS"
# Large status and inbox responses must travel through stdin rather than argv.
jq -n '{BackendState:"Running", Self:{ID:"self", HostName:"local"}, Peer:
  ([range(0;3000) | {key:(tostring), value:{ID:(tostring), HostName:("peer-" + tostring), Online:true}}] | from_entries)}' >"$test_root/status"
test "$(wc -c <"$test_root/status")" -gt 131072
tailscale_snapshot_json false | jq -e '.available and (.peers | length == 3000)' >/dev/null
jq -n '[range(0;5000) | {Name:("file-" + tostring + ".txt"), Size:1}]' >"$test_root/files"
test "$(wc -c <"$test_root/files")" -gt 131072
tailscale_snapshot_json | jq -e '.inboxAvailable and (.files | length == 5000)' >/dev/null
printf '{"BackendState":"Stopped","Self":{},"Peer":{}}' >"$test_root/status"
tailscale_snapshot_json | jq -e '(.connected|not) and (.peers|length == 0)' >/dev/null
printf 'invalid' >"$test_root/status"
tailscale_snapshot_json | jq -e '(.available|not) and (.connected|not) and (.peers|length == 0)' >/dev/null
printf 'tailscale backend tests passed\n'
