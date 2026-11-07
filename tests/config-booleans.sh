#!/usr/bin/env bash
set -euo pipefail
source_root="${1:?source root is required}"
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT
filter="$source_root/src/backend/lib/config-environment.jq"
for field in bar.compact bar.showVram bar.workspaceIcons browserTabs.enable; do
  case "$field" in
    bar.compact)
      variable=DESKTOP_SHELL_BAR_COMPACT
      default=0
      ;;
    bar.showVram)
      variable=DESKTOP_SHELL_BAR_SHOW_VRAM
      default=1
      ;;
    bar.workspaceIcons)
      variable=DESKTOP_SHELL_BAR_WORKSPACE_ICONS
      default=1
      ;;
    browserTabs.enable)
      variable=DESKTOP_SHELL_BROWSER_TABS
      default=0
      ;;
  esac
  for value in true false null missing; do
    if [ "$value" = missing ]; then
      printf '{}\n' >"$test_root/config.json"
    else
      jq -n --arg field "$field" --argjson value "$value" 'setpath($field | split("."); $value)' >"$test_root/config.json"
    fi
    expected="$default"
    case "$value" in true) expected=1 ;; false) expected=0 ;; esac
    actual="$(jq -j -f "$filter" "$test_root/config.json" | tr '\0' '\n' |
      awk -v variable="$variable" '$0 == variable { getline; print; exit }')"
    test "$actual" = "$expected"
  done
  for value in '"false"' '"true"' '""' 0 1 '[]' '{}'; do
    jq -n --arg field "$field" --argjson value "$value" 'setpath($field | split("."); $value)' >"$test_root/config.json"
    if jq -j -f "$filter" "$test_root/config.json" >"$test_root/output" 2>"$test_root/error"; then
      printf 'must reject %s = %s\n' "$field" "$value" >&2
      exit 1
    fi
    # Reject the complete configuration before emitting any environment pairs.
    test ! -s "$test_root/output"
    grep -F "$field" "$test_root/error" >/dev/null
    if DESKTOP_SHELL_CONFIG="$test_root/config.json" \
      bash "$source_root/src/backend/desktop-shell.sh" config show >"$test_root/cli-output" 2>"$test_root/cli-error"; then
      printf 'CLI must reject %s = %s\n' "$field" "$value" >&2
      exit 1
    fi
    test ! -s "$test_root/cli-output"
  done
done
printf 'PASS boolean configuration validation\n'
