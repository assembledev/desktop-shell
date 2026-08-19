#!/usr/bin/env bash

clipboard_list_json() {
  cliphist list 2>/dev/null | jq -Rscf "${BASH_SOURCE[0]%/*}/clipboard-list.jq"
}

clipboard_record_to_stdout() {
  record="${1:-}"
  [ -n "$record" ] || exit 0
  printf '%s' "$record" | base64 -d
}

clipboard_copy() {
  clipboard_record_to_stdout "${1:-}" | cliphist decode | wl-copy
}

clipboard_preview_path() {
  local id="${1:-entry}"
  local kind="${2:-png}"
  local safe_id

  case "$kind" in
    png | jpg | jpeg | webp | bmp | gif) ;;
    *) kind=png ;;
  esac

  safe_id="$(printf '%s\n' "$id" | sed 's/[^A-Za-z0-9_.-]/_/g')"
  printf '%s/%s.%s\n' "$clipboard_preview_dir" "$safe_id" "$kind"
}

clipboard_delete() {
  local record="${1:-}"
  local id="${2:-}"
  local kind="${3:-png}"

  clipboard_record_to_stdout "$record" | cliphist delete
  if [ -n "$id" ]; then
    rm -f -- "$(clipboard_preview_path "$id" "$kind")"
  fi
}

clipboard_preview() {
  record="${1:-}"
  id="${2:-entry}"
  kind="${3:-png}"
  [ -n "$record" ] || exit 0
  preview_path="$(clipboard_preview_path "$id" "$kind")"
  if [ ! -s "$preview_path" ]; then
    clipboard_record_to_stdout "$record" | cliphist decode >"$preview_path" 2>/dev/null || rm -f "$preview_path"
  fi
  [ -s "$preview_path" ] && printf '%s\n' "$preview_path"
}

clipboard_ipc() {
  method="$1"
  desktop_shell_ipc_call clipboardHistory "$method"
}

clipboard_refresh() {
  quickshell ipc --path "${DESKTOP_SHELL_QML}"/shell.qml call clipboardHistory refresh >/dev/null 2>&1 || true
}
