#!/usr/bin/env bash
set -euo pipefail
source_root="$(cd -- "${BASH_SOURCE[0]%/*}/../.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT
cp -R "$source_root/src/modules" "$test_root/modules"
cp "$source_root/tests/native/tailscale-model.qml" "$test_root/shell.qml"
printf '#!%s\n' "$(command -v bash)" >"$test_root/backend"
cat >>"$test_root/backend" <<'SH'
set -eu
if [ "$1" = scenario ]; then printf '%s' "$2" >"$TEST_SCENARIO.next"; mv "$TEST_SCENARIO.next" "$TEST_SCENARIO"; exit; fi
case "$2" in
  peers-json)
    state="$(cat "$TEST_SCENARIO")"
    case "$state" in
      initial) printf '{"available":true,"connected":true,"state":"Running","inboxAvailable":true,"peers":[{"id":"a","name":"A","online":true,"canSend":true,"addresses":["100.64.0.2"],"connection":"idle"},{"id":"b","name":"B","online":true,"canSend":true,"addresses":["100.64.0.3"],"connection":"idle"}],"files":[]}' ;;
      changed | broken) printf '{"available":true,"connected":true,"state":"Running","peers":[{"id":"a","name":"A","online":false,"canSend":false,"addresses":["100.64.0.2"],"connection":"offline"},{"id":"b","name":"B","online":true,"canSend":false,"addresses":["100.64.0.9"],"connection":"idle"}],"files":[]}' ;;
      removed | short-wait) printf '{"available":true,"connected":true,"state":"Running","peers":[],"files":[]}' ;;
    esac
    ;;
  inbox-json) exec python3 "$TEST_INBOX_FIXTURE" "$3" ;;
  ping)
    sleep 0.5
    if [ "$3" = a ]; then printf '{"state":"reachable","milliseconds":1,"connection":"direct"}'; else printf '{"state":"reachable","milliseconds":22,"connection":"peer-relay"}'; fi
    ;;
esac
SH
chmod +x "$test_root/backend"
printf initial >"$test_root/scenario"
export TEST_SCENARIO="$test_root/scenario"
export DESKTOP_SHELL_BACKEND="$test_root/backend"
export TEST_INBOX_FIXTURE="$test_root/inbox.py"
export TEST_INBOX_LOG="$test_root/inbox-log"
cat >"$TEST_INBOX_FIXTURE" <<'PY'
import json
import os
import signal
import sys
import time

wait = int(sys.argv[1])
def log(event):
    with open(os.environ["TEST_INBOX_LOG"], "a") as output:
        output.write(f"{event} {wait} {os.getpid()}\n")
def stopped(*_):
    log("cancelled")
    sys.exit(0)
signal.signal(signal.SIGTERM, stopped)
log("start")
while True:
    state = open(os.environ["TEST_SCENARIO"]).read()
    if state == "broken":
        log("failed")
        sys.exit(1)
    files = [{"Name":"fixture.txt","Size":9}] if state == "changed" else []
    if files or wait == 0 or state == "short-wait":
        print(json.dumps(files))
        log("done")
        break
    time.sleep(0.02)
PY
QT_QPA_PLATFORM=offscreen timeout --kill-after=1s 22s quickshell --no-color --path "$test_root/shell.qml"
# No detached waiting process may survive a disabled model; even unexpectedly
# immediate empty replies must not start an unbounded series of requests.
python3 - "$TEST_INBOX_LOG" <<'PY'
import os
import sys
events = [line.split() for line in open(sys.argv[1])]
starts = [event for event in events if event[:2] == ["start", "3600"]]
assert 2 <= len(starts) <= 4, events
assert any(event[:2] == ["cancelled", "3600"] for event in events), events
for pid in {int(event[2]) for event in events}:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        continue
    raise AssertionError(f"inbox process {pid} survived model shutdown")
PY
