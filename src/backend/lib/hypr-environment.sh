#!/usr/bin/env bash

ensure_hypr_env() {
  if [ -z "${XDG_RUNTIME_DIR:-}" ]; then
    XDG_RUNTIME_DIR="/run/user/$(id -u)"
    export XDG_RUNTIME_DIR
  fi

  # A complete session environment is authoritative. Recover missing values
  # together from Hyprland's own inventory, never from independent directory scans.
  if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && [ -n "${WAYLAND_DISPLAY:-}" ]; then
    return 0
  fi

  local inventory candidates signature display selected_signature='' selected_display='' matches=0
  if ! inventory="$(timeout --kill-after=1s 3s hyprctl -j instances 2>/dev/null)" ||
    ! candidates="$(jq -r \
      --arg signature "${HYPRLAND_INSTANCE_SIGNATURE:-}" \
      --arg display "${WAYLAND_DISPLAY:-}" \
      --arg runtime "$XDG_RUNTIME_DIR" '
      def valid_name: type == "string" and length > 0 and (test("[\u0000-\u001f]") | not);
      def socket_path: if startswith("/") then . else $runtime + "/" + . end;
      if type != "array" or any(.[]; type != "object" or
        (.instance | valid_name | not) or (.wl_socket | valid_name | not))
      then error("invalid compositor inventory") else . end
      | .[]
      | select($signature == "" or .instance == $signature)
      | select($display == "" or (.wl_socket | socket_path) == ($display | socket_path))
      | [.instance, .wl_socket] | @tsv
    ' <<<"$inventory" 2>/dev/null)"; then
    printf 'desktop-shell: could not read compositor instance inventory\n' >&2
    return 1
  fi

  while IFS=$'\t' read -r signature display; do
    [ -n "$signature" ] || continue
    if timeout --kill-after=1s 2s hyprctl -i "$signature" version >/dev/null 2>&1; then
      matches=$((matches + 1))
      selected_signature="$signature"
      selected_display="$display"
    fi
  done <<<"$candidates"

  if [ "$matches" -ne 1 ]; then
    if [ "$matches" -gt 1 ]; then
      printf 'desktop-shell: multiple live compositors; provide WAYLAND_DISPLAY or HYPRLAND_INSTANCE_SIGNATURE\n' >&2
    else
      printf 'desktop-shell: no reachable compositor matches the session environment\n' >&2
    fi
    return 1
  fi

  # Publish the pair only after discovery succeeds; preserve an explicit value.
  export HYPRLAND_INSTANCE_SIGNATURE="${HYPRLAND_INSTANCE_SIGNATURE:-$selected_signature}"
  export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-$selected_display}"
}
