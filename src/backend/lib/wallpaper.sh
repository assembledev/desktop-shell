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
  ensure_hypr_env
  path="$1"
  [ -f "$path" ] || exit 0

  tries=25
  while ! hyprctl hyprpaper listactive >/dev/null 2>&1; do
    [ "$tries" -gt 0 ] || exit 0
    tries=$((tries - 1))
    sleep 0.2
  done

  hyprctl monitors -j |
    jq -r '.[].name' |
    while IFS= read -r monitor; do
      [ -n "$monitor" ] || continue
      hyprctl hyprpaper wallpaper "$monitor,$path,cover" >/dev/null
    done
}

apply_wallpaper() {
  path="$1"
  preview_wallpaper "$path"
  printf '%s\n' "$path" >"$current_wallpaper_file"
  if [ -n "$sddm_wallpaper_sync" ]; then
    "$sddm_wallpaper_sync" "$path" >/dev/null 2>&1 || true
  fi
}
