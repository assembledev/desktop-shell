#!/usr/bin/env bash
set -euo pipefail
source_root="$1"
default_config="$2"
command_test_root="$(mktemp -d)"
trap 'rm -rf "$command_test_root"' EXIT
mkdir -p "$command_test_root/bin" "$command_test_root/runtime"
export XDG_RUNTIME_DIR="$command_test_root/runtime"
export HYPRLAND_INSTANCE_SIGNATURE=test
export WAYLAND_DISPLAY=wayland-test
export DESKTOP_SHELL_QML="$command_test_root/qml"
export COMMAND_TEST_CALLS="$command_test_root/calls"
export COMMAND_TEST_AUDIO="$command_test_root/audio.json"
export COMMAND_TEST_DND="$command_test_root/dnd.json"
export COMMAND_TEST_PROFILE="$command_test_root/profile.json"
export DESKTOP_SHELL_CONFIG="$command_test_root/config.json"
jq '.launcher.profiles = {demo:{applications:[{id:"demo.desktop",workspace:1}]}}' "$default_config" >"$DESKTOP_SHELL_CONFIG"
export DESKTOP_SHELL_DEFAULT_CONFIG="$DESKTOP_SHELL_CONFIG"
printf '%s\n' '{"ready":true,"outputs":[{"id":"43","name":"speaker","volume":50,"muted":false}],"inputs":[{"id":"44","name":"mic","volume":80,"muted":false}],"streams":[],"defaultOutput":{"id":"43"},"defaultInput":{"id":"44"}}' >"$COMMAND_TEST_AUDIO"
printf '%s\n' '{"dnd":false,"count":0}' >"$COMMAND_TEST_DND"
printf '%s\n' '{"id":"demo","snapshotReady":true,"entriesReady":true,"open":1,"placed":1,"total":1,"converged":true,"applying":false,"queued":false,"lastResult":null}' >"$COMMAND_TEST_PROFILE"
printf '#!%s\n' "$(command -v bash)" >"$command_test_root/bin/quickshell"
cat >>"$command_test_root/bin/quickshell" <<'MOCK'
set -euo pipefail
printf '%s\n' "$5/$6" >>"$COMMAND_TEST_CALLS"
case "${COMMAND_TEST_FAILURE:-}" in
  down) exit 1 ;;
  malformed) printf 'Function not found.\n'; exit ;;
  error) printf '{"error":{"code":"unsupported","message":"Not supported"}}\n'; exit ;;
esac
case "$5/$6" in
  audio/status) cat "$COMMAND_TEST_AUDIO" ;;
  audio/command)
    action="$7"; target="$8"; value="$9"
    case "$target" in output) target=43 ;; input) target=44 ;; esac
    jq --arg action "$action" --arg target "$target" --arg value "$value" '
      def update:
        if .id != $target then .
        elif $action == "volume" then .volume = ($value|tonumber)
        elif $action == "mute" then .muted = (if $value == "toggle" then (.muted|not) else $value == "on" end)
        else . end;
      .outputs |= map(update) | .inputs |= map(update)
    ' "$COMMAND_TEST_AUDIO" >"$COMMAND_TEST_AUDIO.tmp"
    mv "$COMMAND_TEST_AUDIO.tmp" "$COMMAND_TEST_AUDIO"
    jq -c --arg action "$action" --arg target "$target" --arg value "$value" '
      ([.outputs[],.inputs[]] | map(select(.id == $target))[0]) as $node
      | {accepted:true,target:$target,name:$node.name}
        + (if $action == "volume" then {volume:($value|tonumber)}
           elif $action == "mute" then {muted:$node.muted} else {direction:$value} end)
    ' "$COMMAND_TEST_AUDIO"
    ;;
  wifi/status) printf '{"available":true,"connected":false,"networks":[]}\n' ;;
  wifi/command) jq -nc --arg action "$7" --arg ssid "$8" '{accepted:true,action:$action,ssid:$ssid}' ;;
  media/status) printf '{"active":null,"players":[]}\n' ;;
  media/command) jq -nc --arg action "$7" --arg player "$8" '{accepted:true,action:$action,player:$player}' ;;
  notifications/status) cat "$COMMAND_TEST_DND" ;;
  notifications/setDnd)
    jq --argjson enabled "$7" '.dnd = $enabled' "$COMMAND_TEST_DND" >"$COMMAND_TEST_DND.tmp"
    mv "$COMMAND_TEST_DND.tmp" "$COMMAND_TEST_DND"
    cat "$COMMAND_TEST_DND"
    ;;
  notifications/list) printf '[]\n' ;;
  notifications/clear) cat "$COMMAND_TEST_DND" ;;
  notifications/dismiss) printf '{"error":{"code":"not-found","message":"No such notification"}}\n' ;;
  launcher/profileReady) printf 'true\n' ;;
  launcher/applyProfile) : ;;
  launcher/profileStatus) cat "$COMMAND_TEST_PROFILE" ;;
  *) exit 1 ;;
esac
MOCK
chmod +x "$command_test_root/bin/quickshell"
export PATH="$command_test_root/bin:$PATH"
cli() { bash "$source_root/src/backend/desktop-shell.sh" "$@"; }
expect_exit() {
  local expected="$1" actual=0
  shift
  "$@" >"$command_test_root/stdout" 2>"$command_test_root/stderr" || actual="$?"
  if [ "$actual" -ne "$expected" ]; then
    printf 'expected exit %s, got %s: %s\n' "$expected" "$actual" "$*" >&2
    cat "$command_test_root/stderr" >&2
    exit 1
  fi
}
# Help and invalid inputs must not require a valid configuration or touch IPC.
printf '{' >"$command_test_root/broken.json"
for topic in audio wifi media dnd notifications profile display brightness bluetooth clipboard; do
  DESKTOP_SHELL_CONFIG="$command_test_root/broken.json" cli "$topic" --help | grep -F 'Usage:' >/dev/null
  DESKTOP_SHELL_CONFIG="$command_test_root/broken.json" cli help "$topic" >/dev/null
done
cli help-all | grep -F 'restart' >/dev/null
expect_exit 2 cli help unknown
expect_exit 2 cli audio volume 151
expect_exit 2 cli audio volume -1
expect_exit 2 cli audio volume nan
expect_exit 2 cli audio mute maybe
expect_exit 2 cli audio default stream 43
expect_exit 2 cli wifi connect
expect_exit 2 cli media next one two
expect_exit 2 cli dnd on extra
[ ! -e "$COMMAND_TEST_CALLS" ]
cli audio status-json | jq -e '.ready and (.outputs|length == 1)' >/dev/null
cli audio devices-json | jq -e '.defaultInput.id == "44"' >/dev/null
cli audio streams-json | jq -e 'length == 0' >/dev/null
cli audio volume 35 | jq -e '.applied and .node.volume == 35' >/dev/null
cli audio mute on input | jq -e '.applied and .node.muted' >/dev/null
cli audio volume 25 input | jq -e '.applied and .node.volume == 25 and .node.muted' >/dev/null
: >"$COMMAND_TEST_CALLS"
cli audio mute toggle input | jq -e '.applied and (.node.muted|not)' >/dev/null
test "$(grep -c '^audio/command$' "$COMMAND_TEST_CALLS")" -eq 1
cli audio default output 43 | jq -e '.applied and .node.id == "43"' >/dev/null
# SSIDs and player IDs stay literal argv values, including shell metacharacters.
# shellcheck disable=SC2016 # The metacharacters must remain literal test data.
ssid='space " quotes; $(touch impossible) ☃'
cli wifi connect "$ssid" | jq -e --arg ssid "$ssid" '.ssid == $ssid and .accepted' >/dev/null
cli wifi networks-json | jq -e 'length == 0' >/dev/null
cli wifi scan | jq -e '.accepted and .action == "scan"' >/dev/null
cli media pause org.mpris.MediaPlayer2.demo | jq -e '.player == "org.mpris.MediaPlayer2.demo" and .action == "pause"' >/dev/null
cli media players-json | jq -e 'length == 0' >/dev/null
cli dnd on | jq -e '.dnd' >/dev/null
cli dnd toggle | jq -e '.dnd | not' >/dev/null
cli notifications list-json | jq -e 'length == 0' >/dev/null
expect_exit 1 cli notifications dismiss missing
cli profile status-json demo | jq -e '.snapshotReady and .converged' >/dev/null
cli profile apply demo --wait | jq -e '.converged' >/dev/null
expect_exit 2 cli profile apply demo --wrong
jq '.lastResult = {success:false,finishedAt:9999999999999}' "$COMMAND_TEST_PROFILE" >"$COMMAND_TEST_PROFILE.tmp"
mv "$COMMAND_TEST_PROFILE.tmp" "$COMMAND_TEST_PROFILE"
expect_exit 1 cli profile apply demo --wait
expect_exit 3 env COMMAND_TEST_FAILURE=down bash "$source_root/src/backend/desktop-shell.sh" audio status-json
expect_exit 3 env COMMAND_TEST_FAILURE=malformed bash "$source_root/src/backend/desktop-shell.sh" media status-json
expect_exit 1 env COMMAND_TEST_FAILURE=error bash "$source_root/src/backend/desktop-shell.sh" wifi on
printf 'Public CLI command contracts passed\n'
