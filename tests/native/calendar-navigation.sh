#!/usr/bin/env bash
set -euo pipefail
source_root="$(cd -- "${BASH_SOURCE[0]%/*}/../.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT
cp -R "$source_root/src/modules" "$test_root/modules"
cp "$source_root/tests/native/calendar-navigation.qml" "$test_root/shell.qml"
QT_QPA_PLATFORM=wayland timeout --kill-after=1s 10s quickshell --no-color --path "$test_root/shell.qml"
