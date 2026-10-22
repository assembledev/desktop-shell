#!/usr/bin/env bash
set -euo pipefail
source_root="$(cd -- "${BASH_SOURCE[0]%/*}/../.." && pwd)"
if [ -z "${WAYLAND_DISPLAY:-}" ]; then
  printf 'network popover focus test requires a Wayland session\n' >&2
  exit 77
fi
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT
# Quickshell imports must stay inside the configuration root.
cp -R "$source_root/src/modules" "$test_root/modules"
cp "$source_root/tests/native/network-popover-focus.qml" "$test_root/shell.qml"
QT_QPA_PLATFORM=wayland timeout --kill-after=1s 10s quickshell --path "$test_root/shell.qml"
