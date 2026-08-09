#!/usr/bin/env bash

ensure_hypr_env() {
  if [ -z "${XDG_RUNTIME_DIR:-}" ]; then
    XDG_RUNTIME_DIR="/run/user/$(id -u)"
    export XDG_RUNTIME_DIR
  fi

  if [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && [ -d "$XDG_RUNTIME_DIR/hypr" ]; then
    sig="$(find "$XDG_RUNTIME_DIR/hypr" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort | tail -n 1 || true)"
    if [ -n "$sig" ]; then
      export HYPRLAND_INSTANCE_SIGNATURE="$sig"
    fi
  fi

  if [ -z "${WAYLAND_DISPLAY:-}" ]; then
    for display in "$XDG_RUNTIME_DIR"/wayland-*; do
      case "$display" in
        *.lock) continue ;;
      esac
      if [ -S "$display" ]; then
        export WAYLAND_DISPLAY="${display##*/}"
        break
      fi
    done
  fi
}
