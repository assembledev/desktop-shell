#!/usr/bin/env bash
set -euo pipefail
source_root="${1:?source root is required}"
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT
# shellcheck source=../src/backend/lib/network.sh
source "$source_root/src/backend/lib/network.sh"
desktop_shell_config="$test_root/config.json"
actions="$test_root/actions"
: >"$actions"
fixture_service_state=active
fixture_backend_state=Running
fixture_api_status=0
fixture_cli_status=0
fixture_helper_status=0
fixture_cli_missing=false
fixture_state_error=false
export DESKTOP_SHELL_TAILSCALE_COMMAND=""

timeout() {
  test "$1" = --signal=TERM
  test "$2" = --kill-after=0.2s
  printf 'timeout %s %s\n' "$3" "$4" >>"$actions"
  shift 3
  "$@"
}
systemctl() {
  test "$1" = is-active
  test "$2" = --
  printf 'service %s\n' "$3" >>"$actions"
  if "$fixture_state_error"; then
    printf 'service manager unavailable\n'
    return 1
  fi
  printf '%s\n' "$fixture_service_state"
  test "$fixture_service_state" = active
}
curl() {
  test "${*: -1}" = http://local-tailscaled.sock/localapi/v0/status
  printf 'api status\n' >>"$actions"
  test "$fixture_api_status" -eq 0 || return "$fixture_api_status"
  jq -nc --arg state "$fixture_backend_state" '{BackendState:$state, Self:{}, Peer:{}}'
}
tailscale() {
  case "$*" in up | down) ;; *)
    printf 'Unexpected CLI status parsing\n' >&2
    return 2
    ;;
  esac
  printf 'cli %s\n' "$*" >>"$actions"
  return "$fixture_cli_status"
}
run_privileged() {
  test "$*" = tailscaled-start
  printf 'privileged %s\n' "$*" >>"$actions"
  return "$fixture_helper_status"
}
command() {
  if [ "${1:-}:${2:-}" = -v:tailscale ] && "$fixture_cli_missing"; then return 1; fi
  builtin command "$@"
}
record_action() { printf '<%s>' "$@" >"$test_root/recorded"; }

# The default has no provider and cannot reach Tailscale, its daemon or authority.
printf '{"bar":{"networkControls":[]}}\n' >"$desktop_shell_config"
if network_control_command tailscale status >"$test_root/output" 2>/dev/null; then exit 1; fi
test ! -s "$actions"
# Custom argv remains literal, even for the already-special Tailscale ID.
jq -n --arg argument $'first\nsecond; $(touch unsafe)' '{bar:{networkControls:[{
  id:"tailscale", label:"Custom", statusCommand:["printf","<%s>",$argument,"","last"], toggleCommand:["true"]
}]}}' >"$desktop_shell_config"
test "$(network_control_command tailscale status)" = $'<first\nsecond; $(touch unsafe)><><last>'
network_control_command tailscale toggle
test ! -s "$actions"
# Reject incomplete modes, duplicate IDs and malformed argv before any action.
cp "$desktop_shell_config" "$test_root/custom.json"
for expression in \
  '.bar.networkControls[0].toggleCommand = []' \
  '.bar.networkControls[0].statusCommand = ["touch", "unsafe", null]' \
  '.bar.networkControls[0].unit = "demo.service"' \
  '.bar.networkControls += .bar.networkControls'; do
  jq "$expression" "$test_root/custom.json" >"$desktop_shell_config"
  if network_control_command tailscale status >"$test_root/output" 2>/dev/null; then exit 1; fi
done
test ! -s "$actions"

printf '{"bar":{"networkControls":[{"id":"tailscale","label":"Tail"}]}}\n' >"$desktop_shell_config"
# Native status reuses the LocalAPI owner without querying Taildrop or the CLI.
for fixture_backend_state in Running NeedsLogin NeedsMachineAuth NoState Stopped Starting; do
  network_control_command tailscale status >"$test_root/output"
  case "$fixture_backend_state" in
    Running) jq -e '.text == "Tail" and .active and (.login | not)' "$test_root/output" >/dev/null ;;
    NeedsLogin | NeedsMachineAuth) jq -e '(.active | not) and .login' "$test_root/output" >/dev/null ;;
    Starting) jq -e '.text == "Tail…" and (.active | not) and (.login | not)' "$test_root/output" >/dev/null ;;
    *) jq -e '.text == "Tail" and (.active | not) and (.login | not)' "$test_root/output" >/dev/null ;;
  esac
done
! grep -Eq '^(cli|privileged)' "$actions"
test "$(grep -c '^api status' "$actions")" -eq 6
for fixture_backend_state in InUseOtherUser FutureUnsupportedState; do
  if network_control_command tailscale status >"$test_root/output" 2>/dev/null; then exit 1; fi
  if network_control_command tailscale toggle >"$test_root/output" 2>/dev/null; then exit 1; fi
done
fixture_backend_state=Running
fixture_api_status=28
if network_control_command tailscale status >"$test_root/output" 2>/dev/null; then exit 1; fi
fixture_api_status=0
fixture_service_state=failed
if network_control_command tailscale status >"$test_root/output" 2>/dev/null; then exit 1; fi
fixture_state_error=true
if network_control_command tailscale status >"$test_root/output" 2>/dev/null; then exit 1; fi
fixture_state_error=false
for fixture_service_state in inactive deactivating activating; do
  : >"$actions"
  network_control_command tailscale status >"$test_root/output"
  jq -e '(.active | not) and (.login | not)' "$test_root/output" >/dev/null
  ! grep -q '^api ' "$actions"
done
# A running daemon uses user/operator permissions for both connect and disconnect.
fixture_service_state=active
fixture_backend_state=Running
: >"$actions"
network_control_command tailscale toggle
grep -q '^timeout 10s tailscale$' "$actions"
grep -q '^cli down$' "$actions"
! grep -q '^privileged ' "$actions"
for fixture_backend_state in NoState NeedsLogin NeedsMachineAuth Stopped; do
  : >"$actions"
  network_control_command tailscale toggle
  ! grep -q '^privileged ' "$actions"
  grep -q '^timeout 20s tailscale$' "$actions"
  grep -q '^cli up$' "$actions"
done
fixture_service_state=inactive
: >"$actions"
network_control_command tailscale toggle
grep -q '^privileged tailscaled-start$' "$actions"
grep -q '^cli up$' "$actions"
fixture_service_state=active
fixture_backend_state=Starting
: >"$actions"
if network_control_command tailscale toggle >"$test_root/output" 2>/dev/null; then exit 1; fi
! grep -Eq '^(cli|privileged)' "$actions"
fixture_service_state=deactivating
: >"$actions"
if network_control_command tailscale toggle >"$test_root/output" 2>/dev/null; then exit 1; fi
! grep -Eq '^(cli|privileged)' "$actions"
fixture_service_state=active
fixture_backend_state=Stopped
fixture_cli_missing=true
: >"$actions"
if network_control_command tailscale toggle >"$test_root/output" 2>"$test_root/error"; then exit 1; fi
grep -q 'Tailscale CLI is required' "$test_root/error"
! grep -Eq '^(cli|privileged)' "$actions"
fixture_cli_missing=false
fixture_service_state=inactive
fixture_helper_status=1
: >"$actions"
if network_control_command tailscale toggle >"$test_root/output" 2>/dev/null; then exit 1; fi
! grep -q '^cli ' "$actions"
fixture_helper_status=0
fixture_cli_status=124
if network_control_command tailscale toggle >"$test_root/output" 2>/dev/null; then exit 1; fi
fixture_cli_status=0

# The generated executable binding wins over PATH, including paths with spaces.
configured_cli="$test_root/configured tailscale"
printf '#!%s\n' "$(command -v bash)" >"$configured_cli"
cat >>"$configured_cli" <<'CLI'
printf 'configured cli %s\n' "$*" >>"$NETWORK_CONTROL_ACTIONS"
CLI
chmod +x "$configured_cli"
export NETWORK_CONTROL_ACTIONS="$actions"
jq --arg executable "$configured_cli" '.integrations.tailscaleCommand = $executable' \
  "$desktop_shell_config" >"$test_root/bound-config.json"
while IFS= read -r -d '' config_key && IFS= read -r -d '' config_value; do
  if [ "$config_key" = DESKTOP_SHELL_TAILSCALE_COMMAND ]; then
    export DESKTOP_SHELL_TAILSCALE_COMMAND="$config_value"
  fi
done < <(jq -je -f "$source_root/src/backend/lib/config-environment.jq" "$test_root/bound-config.json")
test "$DESKTOP_SHELL_TAILSCALE_COMMAND" = "$configured_cli"
fixture_service_state=active
fixture_cli_missing=true
for fixture_backend_state in Running Stopped; do
  : >"$actions"
  network_control_command tailscale toggle
  if [ "$fixture_backend_state" = Running ]; then expected_action=down; else expected_action=up; fi
  grep -q "^configured cli $expected_action$" "$actions"
  ! grep -Eq '^(cli|privileged)' "$actions"
done
# A broken explicit binding fails instead of silently choosing another package.
export DESKTOP_SHELL_TAILSCALE_COMMAND="$test_root/missing tailscale"
: >"$actions"
if network_control_command tailscale toggle >"$test_root/output" 2>/dev/null; then exit 1; fi
! grep -Eq '^(cli|configured cli|privileged)' "$actions"
export DESKTOP_SHELL_TAILSCALE_COMMAND=""
fixture_cli_missing=false

# Systemd service controls reuse state handling and execute only configured argv.
jq -n --arg argument $'arg\nwith "quotes"; $(touch unsafe)' '{bar:{networkControls:[{
  id:"work", label:"Work", unit:"example-work.service",
  startCommand:["record_action","start",$argument], stopCommand:["record_action","stop",$argument],
  retryCommand:["record_action","retry",$argument]
}]}}' >"$desktop_shell_config"
for fixture_service_state in active inactive activating deactivating failed; do
  network_control_command work status >"$test_root/output"
  jq -e --arg state "$fixture_service_state" '.active == ($state == "active") and .login == ($state == "failed")' "$test_root/output" >/dev/null
  rm -f "$test_root/recorded"
  case "$fixture_service_state" in
    activating | deactivating)
      if network_control_command work toggle >"$test_root/output" 2>/dev/null; then exit 1; fi
      test ! -e "$test_root/recorded"
      ;;
    *)
      network_control_command work toggle
      case "$fixture_service_state" in active) expected_action=stop ;; inactive) expected_action=start ;; failed) expected_action=retry ;; esac
      test "$(cat "$test_root/recorded")" = "<$expected_action>"$'<arg\nwith "quotes"; $(touch unsafe)>'
      ;;
  esac
done
cp "$desktop_shell_config" "$test_root/service.json"
for expression in '.bar.networkControls[0].retryCommand = []' '.bar.networkControls[0].startCommand = ["touch", "unsafe", 2]'; do
  jq "$expression" "$test_root/service.json" >"$desktop_shell_config"
  rm -f "$test_root/recorded"
  if network_control_command work toggle >"$test_root/output" 2>/dev/null; then exit 1; fi
  test ! -e "$test_root/recorded"
done
printf 'network control tests passed\n'
