#!/usr/bin/env bash

# Keep capture times across shell restarts; old cliphist records have unknown ages.
clipboard_age_file() {
  printf '%s/desktop-shell/clipboard-ages.json\n' "${XDG_STATE_HOME:-$HOME/.local/state}"
}

clipboard_parse_list() {
  local ages
  ages="$(clipboard_age_file)"
  [ -r "$ages" ] || ages=/dev/null
  jq -Rsc --slurpfile ages "$ages" --argjson capturedAt "${1:-0}" \
    --arg previous "${2:-}" -f "${BASH_SOURCE[0]%/*}/clipboard-list.jq"
}

clipboard_list_json() {
  cliphist list 2>/dev/null | clipboard_parse_list
}

# Serialize both watchers and destructive history actions. The lock is released
# before IPC, and neither readers nor clipboard copies need to acquire it.
clipboard_age_lock() {
  ages="$(clipboard_age_file)"
  mkdir -p "${ages%/*}"
  umask 077
  exec 9>"$ages.lock"
  flock 9
}

clipboard_store() (
  set -euo pipefail
  clipboard_age_lock
  before="$(cliphist list 2>/dev/null)" || before=""
  before="${before%%$'\n'*}"
  before="$(printf '%s' "$before" | base64 -w0)"
  printf -v captured_at '%(%s)T' -1
  cliphist store
  after="$(cliphist list 2>/dev/null)" || exit 0
  age_tmp="$(mktemp "$ages.XXXXXX")"
  trap 'rm -f -- "$age_tmp"' EXIT
  printf '%s\n' "$after" | clipboard_parse_list "$captured_at" "$before" |
    jq 'map(select(.createdAt > 0) | {key: .entryId, value: {record, createdAt}}) | from_entries' >"$age_tmp"
  mv -f -- "$age_tmp" "$ages"
)

clipboard_forget_age() {
  [ -f "$ages" ] || return 0
  local age_tmp
  age_tmp="$(mktemp "$ages.XXXXXX")"
  if jq --arg id "$1" 'del(.[$id])' "$ages" >"$age_tmp"; then
    mv -f -- "$age_tmp" "$ages"
  else
    rm -f -- "$age_tmp"
    return 1
  fi
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

clipboard_delete() (
  set -euo pipefail
  clipboard_age_lock
  local record="${1:-}"
  local id="${2:-}"
  local kind="${3:-png}"

  clipboard_record_to_stdout "$record" | cliphist delete
  if [ -n "$id" ]; then
    rm -f -- "$(clipboard_preview_path "$id" "$kind")"
    clipboard_forget_age "$id"
  fi
)

clipboard_wipe() (
  set -euo pipefail
  clipboard_age_lock
  cliphist wipe
  rm -f -- "$ages"
  find "$clipboard_preview_dir" -mindepth 1 -maxdepth 1 -delete
)

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
