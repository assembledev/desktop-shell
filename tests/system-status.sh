#!/usr/bin/env bash

set -euo pipefail

source_root="${1:?source root is required}"
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT
# shellcheck source=../src/backend/lib/system-status.sh
source "$source_root/src/backend/lib/system-status.sh"

mkdir -p "$test_root/profiles" "$test_root/old/specialisation" "$test_root/new" "$test_root/test" "$test_root/special" "$test_root/bin"
ln -s "$test_root/old" "$test_root/profiles/system-1-link"
ln -s "$test_root/new" "$test_root/profiles/system-2-link"
ln -s system-2-link "$test_root/profiles/system"
ln -s "$test_root/special" "$test_root/old/specialisation/demo"
ln -s "$test_root/old" "$test_root/current"

printf '#!%s\n' "$(command -v bash)" >"$test_root/bin/nix"
cat >>"$test_root/bin/nix" <<'EOF'
set -eu
test "$1" = path-info
test "$2" = --extra-experimental-features
test "$3" = read-only-local-store
test "$4" = --store
test "$5" = 'local?read-only=true'
test "$6" = --json
test "$7" = --json-format
test "$8" = 1
jq -n --arg path "$9" '{($path): {registrationTime: 1791522859}}'
EOF
chmod +x "$test_root/bin/nix"
export PATH="$test_root/bin:$PATH"

# Running an older retained generation remains switch even if another is selected.
system_status_json "$test_root/current" "$test_root/profiles" |
  jq -e '.available and .state == "switch" and .registrationTime == 1791522859' >/dev/null
ln -sfn "$test_root/test" "$test_root/current"
system_status_json "$test_root/current" "$test_root/profiles" |
  jq -e '.available and .state == "test"' >/dev/null
ln -sfn "$test_root/special" "$test_root/current"
system_status_json "$test_root/current" "$test_root/profiles" |
  jq -e '.available and .state == "switch"' >/dev/null

# Metadata failure must not invent a timestamp or alter the inferred state.
printf '#!%s\nexit 1\n' "$(command -v bash)" >"$test_root/bin/nix"
system_status_json "$test_root/current" "$test_root/profiles" |
  jq -e '.available and .state == "switch" and .registrationTime == null' >/dev/null
system_status_json "$test_root/missing" "$test_root/profiles" |
  jq -e '.available == false' >/dev/null
