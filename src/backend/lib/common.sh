#!/usr/bin/env bash

set -eu

# shellcheck source=hypr-environment.sh
source "${BASH_SOURCE[0]%/*}/hypr-environment.sh"

desktop_shell_config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
desktop_shell_config="${DESKTOP_SHELL_CONFIG:-$desktop_shell_config_home/desktop-shell/config.json}"
if [ ! -r "$desktop_shell_config" ]; then
  desktop_shell_config="${DESKTOP_SHELL_DEFAULT_CONFIG:?DESKTOP_SHELL_DEFAULT_CONFIG is not set}"
fi
if ! jq -e 'type == "object"' "$desktop_shell_config" >/dev/null 2>&1; then
  printf 'desktop-shell: invalid configuration: %s\n' "$desktop_shell_config" >&2
  exit 1
fi

config_string() {
  key="$1"
  jq -r "$key // empty | strings" "$desktop_shell_config"
}

export DESKTOP_SHELL_CONFIG="$desktop_shell_config"
export DESKTOP_SHELL_WORKSPACES_JSON="$(jq -c '.workspaces.items // []' "$desktop_shell_config")"
export DESKTOP_SHELL_SCROLLING_WORKSPACE="$(config_string '.workspaces.scrolling')"
export DESKTOP_SHELL_OUTPUT="$(config_string '.output')"
export DESKTOP_SHELL_BAR_COMPACT="$(jq -r 'if .bar.compact // false then "1" else "0" end' "$desktop_shell_config")"
export DESKTOP_SHELL_BAR_SHOW_VRAM="$(jq -r 'if .bar.showVram // true then "1" else "0" end' "$desktop_shell_config")"
export DESKTOP_SHELL_BAR_WORKSPACE_ICONS="$(jq -r 'if .bar.workspaceIcons // true then "1" else "0" end' "$desktop_shell_config")"
export DESKTOP_SHELL_KEYBOARD_LABELS_JSON="$(jq -c '.keyboard.layoutLabels // ["EN"]' "$desktop_shell_config")"
export DESKTOP_SHELL_BROWSER_TABS="$(jq -r 'if .browserTabs.enable // false then "1" else "0" end' "$desktop_shell_config")"
export DESKTOP_SHELL_BROWSER_ENTRY_ID="$(config_string '.browserTabs.desktopEntryId')"
export DESKTOP_SHELL_BROWSER_NAME="$(config_string '.browserTabs.displayName')"
export DESKTOP_SHELL_BROWSER_ICON="$(config_string '.browserTabs.icon')"
export DESKTOP_SHELL_THEME_JSON="$(jq -c '.theme // {}' "$desktop_shell_config")"
export DESKTOP_SHELL_NETWORK_CONTROLS="$desktop_shell_config"
export DESKTOP_SHELL_HOTKEYS_JSON="$desktop_shell_config"
export DESKTOP_SHELL_LOCK_KEYBOARD_INDEX="$(config_string '.lock.keyboardLayoutIndex')"
export DESKTOP_SHELL_SDDM_WALLPAPER_SYNC="$(config_string '.integrations.sddmWallpaperSync')"
export DESKTOP_SHELL_PRIVILEGED_HELPER="$(config_string '.integrations.privilegedHelper')"

recording_state_file="$(config_string '.integrations.recordingStateFile')"
if [ -n "$recording_state_file" ] && [ "${recording_state_file#/}" = "$recording_state_file" ]; then
  recording_state_file="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/$recording_state_file"
fi
export DESKTOP_SHELL_RECORDING_STATE="$recording_state_file"

desktop_shell_state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/desktop-shell"
state_dir="$desktop_shell_state_dir"
wallpaper_state_dir="$desktop_shell_state_dir/wallpaper"
current_wallpaper_file="$wallpaper_state_dir/current"
clipboard_preview_dir="$state_dir/clipboard-previews"
wallpaper_dir="$(config_string '.wallpaper.directory')"
[ -n "$wallpaper_dir" ] || wallpaper_dir="$HOME/Wallpapers"
default_wallpaper="$(config_string '.wallpaper.default')"
[ -n "$default_wallpaper" ] || default_wallpaper="$wallpaper_dir/wallpaper.jpg"
sddm_wallpaper_sync="$DESKTOP_SHELL_SDDM_WALLPAPER_SYNC"
privileged_helper="$DESKTOP_SHELL_PRIVILEGED_HELPER"
desktop_shell_executable="${DESKTOP_SHELL_EXECUTABLE:-$0}"
system_sys_root="${DESKTOP_SHELL_SYS_ROOT:-/sys}"
system_proc_root="${DESKTOP_SHELL_PROC_ROOT:-/proc}"
mkdir -p "$desktop_shell_state_dir" "$state_dir" "$wallpaper_state_dir" "$wallpaper_dir" "$clipboard_preview_dir"

# Keep existing user state when upgrading from the former NixOS-local layout.
legacy_state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/control-center"
legacy_wallpaper_state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/wallpaper-picker"
for state_name in count dnd focus; do
  if [ ! -e "$state_dir/$state_name" ] && [ -r "$legacy_state_dir/$state_name" ]; then
    cp "$legacy_state_dir/$state_name" "$state_dir/$state_name"
  fi
done
if [ ! -e "$current_wallpaper_file" ] && [ -r "$legacy_wallpaper_state_dir/current" ]; then
  cp "$legacy_wallpaper_state_dir/current" "$current_wallpaper_file"
fi
[ -f "$state_dir/count" ] || printf '0\n' >"$state_dir/count"
[ -f "$state_dir/dnd" ] || printf '0\n' >"$state_dir/dnd"
[ -f "$state_dir/focus" ] || printf '0\n' >"$state_dir/focus"

json_escape() {
  jq -Rs .
}

run_privileged() {
  if [ -z "$privileged_helper" ]; then
    printf 'desktop-shell: privileged helper is not configured for this host\n' >&2
    return 1
  fi
  /run/wrappers/bin/sudo "$privileged_helper" "$@"
}
