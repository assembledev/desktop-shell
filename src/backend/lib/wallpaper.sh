#!/usr/bin/env bash

find_wallpapers() {
  find "$wallpaper_dir" \
    -type f \
    \( -iname '*.avif' -o -iname '*.bmp' -o -iname '*.gif' -o -iname '*.heic' -o -iname '*.jpeg' -o -iname '*.jpg' -o -iname '*.jxl' -o -iname '*.png' -o -iname '*.svg' -o -iname '*.tif' -o -iname '*.tiff' -o -iname '*.webp' \) \
    -print0 2>/dev/null | sort -zu
}

list_wallpapers_json() {
  find_wallpapers |
    jq -Rs --arg dir "$wallpaper_dir/" '
        split("\u0000")[:-1]
        | map({
            path: .,
            relativePath: (if startswith($dir) then .[($dir | length):] else . end),
            name: (split("/")[-1])
          })
      '
}

read_current_wallpaper() {
  if [ -f "$current_wallpaper_file" ]; then
    cat "$current_wallpaper_file"
  else
    printf '%s\n' "$default_wallpaper"
  fi
}

preview_wallpaper() {
  local path="$1" tries=25 snapshot monitors monitor
  ensure_hypr_env
  if [ ! -f "$path" ] || [ ! -r "$path" ]; then
    printf 'desktop-shell: Wallpaper image is not readable\n' >&2
    return 1
  fi

  while ! timeout --kill-after=1s 1s hyprctl hyprpaper listactive >/dev/null 2>&1; do
    if [ "$tries" -eq 0 ]; then
      printf 'desktop-shell: hyprpaper is not responding\n' >&2
      return 1
    fi
    tries=$((tries - 1))
    sleep 0.2
  done

  if ! snapshot="$(timeout --kill-after=1s 8s hyprctl monitors -j 2>/dev/null)" ||
    ! monitors="$(jq -er '[.[].name | select(type == "string" and length > 0)] | if length == 0 then empty else .[] end' <<<"$snapshot")"; then
    printf 'desktop-shell: Could not read connected displays\n' >&2
    return 1
  fi
  while IFS= read -r monitor; do
    if ! timeout --kill-after=1s 8s hyprctl hyprpaper wallpaper "$monitor,$path,cover" >/dev/null; then
      printf 'desktop-shell: Could not apply wallpaper to %s\n' "$monitor" >&2
      return 1
    fi
  done <<<"$monitors"
}

apply_wallpaper() {
  local path="$1"
  preview_wallpaper "$path" || return 1
  printf '%s\n' "$path" >"$current_wallpaper_file" || return 1
  if [ -n "$login_wallpaper_sync" ]; then
    # Greeter cache synchronization is best-effort after the session selection.
    timeout --kill-after=1s 5s "$login_wallpaper_sync" "$path" >/dev/null 2>&1 || true
  fi
}
