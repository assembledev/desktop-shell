#!/usr/bin/env bash

# Read-only diagnostics are usable before common.sh initializes runtime state.
doctor_probe() {
  timeout --kill-after=1s 3s "$@" 2>/dev/null
}

doctor_browser_tabs() {
  local config="$1" view host state snapshot
  if ! view="$(doctor_probe quickshell ipc --path "${DESKTOP_SHELL_QML}/shell.qml" call launcher browserStatus)" ||
    ! jq -e 'type == "object" and .ready == true and (.enabled | type == "boolean")' <<<"$view" >/dev/null 2>&1; then
    printf 'browser-tabs: launcher diagnostics unavailable\n'
    return 1
  fi
  if ! jq -en --argjson view "$view" --argjson configured "$config" '$view.enabled == $configured' >/dev/null; then
    printf 'browser-tabs: running configuration differs; restart the shell after applying configuration\n'
    return 1
  fi
  if [ "$config" = false ]; then
    printf 'browser-tabs: disabled\n'
    return 0
  fi
  if [ -z "${DESKTOP_SHELL_BROWSER_BRIDGE:-}" ] ||
    ! host="$(doctor_probe "$DESKTOP_SHELL_BROWSER_BRIDGE" status)" ||
    ! jq -e 'type == "object" and (.connected | type == "boolean")' <<<"$host" >/dev/null 2>&1; then
    printf 'browser-tabs: native host diagnostics unavailable\n'
    return 1
  fi
  if jq -e '.connected == false' <<<"$host" >/dev/null; then
    if jq -e '.snapshotPresent == true' <<<"$host" >/dev/null || jq -e '.connected == true' <<<"$view" >/dev/null; then
      printf 'browser-tabs: stale snapshot; native host is disconnected\n'
      return 1
    fi
    printf 'browser-tabs: disconnected (browser or extension is not connected)\n'
    return 0
  fi
  if ! jq -e '(.generatedAt | type == "number") and .generatedAt > 0' <<<"$host" >/dev/null; then
    printf 'browser-tabs: native host connected, waiting for the first browser snapshot\n'
    return 1
  fi
  state="${XDG_RUNTIME_DIR}/desktop-shell/browser-tabs.json"
  if ! snapshot="$(jq -ec '
    select(.version == 1 and .connected == true and (.session | type == "string")
      and (.generatedAt | type == "number") and (.tabs | type == "array"))
    | {session, generatedAt}' "$state" 2>/dev/null)"; then
    printf 'browser-tabs: native host connected, snapshot missing or invalid\n'
    return 1
  fi
  if ! jq -en --argjson host "$host" --argjson snapshot "$snapshot" --argjson view "$view" '
    $host.ok == true and $host.version == 1 and $view.connected == true
    and $host.session == $snapshot.session and $host.session == $view.session
    and $host.generatedAt == $snapshot.generatedAt and $host.generatedAt == $view.generatedAt
  ' >/dev/null; then
    printf 'browser-tabs: snapshot mismatch (updating or not loaded by launcher); rerun to distinguish\n'
    return 1
  fi
  printf 'browser-tabs: ready (native host and launcher agree)\n'
}

doctor() {
  # shellcheck source=hypr-environment.sh
  source "${BASH_SOURCE[0]%/*}/hypr-environment.sh"
  local failures=0 config_valid=false command reply browser_enabled desktop_shell_config
  desktop_shell_config="${DESKTOP_SHELL_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/desktop-shell/config.json}"
  if [ ! -r "$desktop_shell_config" ]; then
    desktop_shell_config="${DESKTOP_SHELL_DEFAULT_CONFIG:-}"
  fi
  if jq -je -f "${BASH_SOURCE[0]%/*}/config-environment.jq" "$desktop_shell_config" >/dev/null 2>&1; then
    printf 'config: ok (%s)\n' "$desktop_shell_config"
    config_valid=true
  else
    printf 'config: invalid (%s)\n' "$desktop_shell_config"
    failures=$((failures + 1))
  fi
  for command in quickshell hyprctl jq systemctl timeout; do
    if command -v "$command" >/dev/null 2>&1; then
      printf '%s: ok\n' "$command"
    else
      printf '%s: missing\n' "$command"
      failures=$((failures + 1))
    fi
  done
  if ensure_hypr_env && doctor_probe hyprctl version >/dev/null; then
    printf 'hyprland: reachable\n'
  else
    printf 'hyprland: not reachable\n'
    failures=$((failures + 1))
  fi
  if doctor_probe systemctl --user --quiet is-active desktop-shell.service; then
    printf 'service: active\n'
  else
    printf 'service: inactive or unavailable\n'
    failures=$((failures + 1))
  fi
  if [ -n "${DESKTOP_SHELL_QML:-}" ] &&
    reply="$(doctor_probe quickshell ipc --path "$DESKTOP_SHELL_QML/shell.qml" call desktopShell ping)" &&
    [ "$reply" = true ]; then
    printf 'shell-ipc: ready\n'
    if [ "$config_valid" = true ]; then
      browser_enabled="$(jq -r '.browserTabs.enable // false | if . then "true" else "false" end' "$desktop_shell_config")"
      if ! doctor_browser_tabs "$browser_enabled"; then failures=$((failures + 1)); fi
    else
      printf 'browser-tabs: not checked (invalid configuration)\n'
    fi
  else
    printf 'shell-ipc: unavailable or incompatible; service activity alone does not prove readiness\n'
    printf 'browser-tabs: not checked (shell IPC unavailable)\n'
    failures=$((failures + 1))
  fi
  [ "$failures" -eq 0 ]
}
