#!/usr/bin/env bash

set -eu

# shellcheck source=hypr-environment.sh
source "${BASH_SOURCE[0]%/*}/hypr-environment.sh"

desktop_shell_config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
desktop_shell_config="${DESKTOP_SHELL_CONFIG:-$desktop_shell_config_home/desktop-shell/config.json}"
if [ ! -r "$desktop_shell_config" ]; then
  desktop_shell_config="${DESKTOP_SHELL_DEFAULT_CONFIG:?DESKTOP_SHELL_DEFAULT_CONFIG is not set}"
fi
# Parse once for all backend commands. NUL-delimited name/value pairs preserve
# whitespace and shell metacharacters without evaluating configuration as code.
while IFS= read -r -d '' config_key && IFS= read -r -d '' config_value; do
  printf -v "$config_key" '%s' "$config_value"
  case "$config_key" in
    DESKTOP_SHELL_*) export "${config_key?}" ;;
  esac
done < <(jq -je -f "${BASH_SOURCE[0]%/*}/config-environment.jq" "$desktop_shell_config" 2>/dev/null)
config_reader_pid=$!
if ! wait "$config_reader_pid"; then
  printf 'desktop-shell: invalid configuration: %s\n' "$desktop_shell_config" >&2
  exit 1
fi
unset config_key config_value config_reader_pid

export DESKTOP_SHELL_CONFIG="$desktop_shell_config"
export DESKTOP_SHELL_NETWORK_CONTROLS="$desktop_shell_config"
export DESKTOP_SHELL_HOTKEYS_JSON="$desktop_shell_config"

if [ -n "$recording_state_file" ] && [ "${recording_state_file#/}" = "$recording_state_file" ]; then
  recording_state_file="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/$recording_state_file"
fi
export DESKTOP_SHELL_RECORDING_STATE="$recording_state_file"

desktop_shell_state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/desktop-shell"
state_dir="$desktop_shell_state_dir"
preferences_state_dir="$desktop_shell_state_dir/preferences"
wallpaper_state_dir="$desktop_shell_state_dir/wallpaper"
display_state_dir="$desktop_shell_state_dir/displays"
current_wallpaper_file="$wallpaper_state_dir/current"
clipboard_preview_dir="$state_dir/clipboard-previews"
[ -n "$wallpaper_dir" ] || wallpaper_dir="$HOME/Wallpapers"
[ -n "$default_wallpaper" ] || default_wallpaper="$wallpaper_dir/wallpaper.jpg"
login_wallpaper_sync="$DESKTOP_SHELL_LOGIN_WALLPAPER_SYNC"
privileged_helper="$DESKTOP_SHELL_PRIVILEGED_HELPER"
desktop_shell_executable="${DESKTOP_SHELL_EXECUTABLE:-$0}"
system_sys_root="${DESKTOP_SHELL_SYS_ROOT:-/sys}"
system_proc_root="${DESKTOP_SHELL_PROC_ROOT:-/proc}"
mkdir -p "$desktop_shell_state_dir" "$state_dir" "$preferences_state_dir" "$wallpaper_state_dir" "$display_state_dir" "$wallpaper_dir" "$clipboard_preview_dir"

[ -f "$state_dir/count" ] || printf '0\n' >"$state_dir/count"
[ -f "$preferences_state_dir/dnd" ] || printf '0\n' >"$preferences_state_dir/dnd"
[ -f "$preferences_state_dir/focus" ] || printf '0\n' >"$preferences_state_dir/focus"

write_preference() {
  local preference_name="$1"
  local preference_value="$2"
  local preference_tmp
  case "$preference_name" in
    dnd | focus) ;;
    *)
      printf 'desktop-shell: invalid preference: %s\n' "$preference_name" >&2
      return 2
      ;;
  esac

  preference_tmp="$(mktemp "$preferences_state_dir/.${preference_name}.XXXXXX")"
  if ! printf '%s\n' "$preference_value" >"$preference_tmp" || ! mv -f "$preference_tmp" "$preferences_state_dir/$preference_name"; then
    rm -f "$preference_tmp"
    return 1
  fi
}

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
