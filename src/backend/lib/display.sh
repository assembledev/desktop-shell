#!/usr/bin/env bash

# Display policy has two owners: Nix supplies the baseline Hyprland monitor
# rules, while confirmed Control Center changes are runtime overlays stored by
# physical output identity. `desktop-shell display reset` removes the overlays
# and reloads the declarative baseline.

display_runtime_dir="${XDG_RUNTIME_DIR:?XDG_RUNTIME_DIR is not set}/desktop-shell"
display_profiles_file="$display_state_dir/profiles.json"
display_pending_file="$display_runtime_dir/display-pending.json"
display_lock_file="$display_runtime_dir/display.lock"
display_confirm_seconds="${DESKTOP_SHELL_DISPLAY_CONFIRM_SECONDS:-20}"
mkdir -p "$display_runtime_dir"

display_profiles_init() {
  if [ ! -r "$display_profiles_file" ] || ! jq -e '.version == 1 and (.profiles | type == "array")' "$display_profiles_file" >/dev/null 2>&1; then
    printf '%s\n' '{"version":1,"profiles":[]}' >"$display_profiles_file"
  fi
}

display_snapshot_json() {
  local monitors

  ensure_hypr_env
  monitors="$(hyprctl monitors all -j)" || return

  jq -ce '
    def trimmed: tostring | sub("[[:space:]]+$"; "");
    def mode_refresh:
      capture("@(?<refresh>[0-9.]+)").refresh | tonumber;
    def current_mode($modes; $width; $height; $refresh):
      if $width <= 0 or $height <= 0 then
        ($modes[0] // "preferred")
      else
        ([
          $modes[]
          | select(startswith(($width | tostring) + "x" + ($height | tostring) + "@"))
          | { mode: ., delta: ((mode_refresh - $refresh) | if . < 0 then -. else . end) }
        ] | min_by(.delta).mode) // (($width | tostring) + "x" + ($height | tostring) + "@" + ($refresh | tostring))
      end;
    . as $raw
    | [
        $raw[]
        | (.availableModes // [] | map(sub("Hz$"; ""))) as $modes
        | {
            id,
            name,
            description: ((.description // .name) | trimmed),
            make: ((.make // "") | trimmed),
            model: ((.model // "") | trimmed),
            serial: ((.serial // "") | trimmed),
            internal: ((.name // "") | test("^(eDP|LVDS|DSI)(-|$)"; "i")),
            enabled: ((.disabled // false) | not),
            focused: (.focused // false),
            width: (.width // 0),
            height: (.height // 0),
            refreshRate: (.refreshRate // 0),
            x: (.x // 0),
            y: (.y // 0),
            position: ((.x // 0) | tostring) + "x" + ((.y // 0) | tostring),
            scale: (if ((.scale // 0) | tonumber) > 0 then .scale else 1 end),
            mirrorId: (.mirrorOf // "none"),
            availableModes: $modes,
            mode: current_mode($modes; (.width // 0); (.height // 0); (.refreshRate // 0))
          }
      ] as $outputs
    | [
        $outputs[]
        | . as $output
        | . + {
            mirror: (
              if (.mirrorId | tostring) == "none" then ""
              else ([ $outputs[] | select((.id | tostring) == ($output.mirrorId | tostring)) | .name ][0] // "")
              end
            ),
            baseIdentity: (
              if .serial != "" then "edid:" + .make + "|" + .model + "|" + .serial
              elif .description != "" then "description:" + .description
              else "connector:" + .name
              end
            )
          }
      ] as $identified
    | [
        $identified[]
        | . as $output
        | . + {
            identity: (
              if ([ $identified[] | select(.baseIdentity == $output.baseIdentity) ] | length) > 1
              then .baseIdentity + "|connector:" + .name
              else .baseIdentity
              end
            )
          }
        | del(.mirrorId, .baseIdentity)
      ] as $result
    | {
        supported: true,
        topology: ($result | map(.identity) | sort | join("\u001f")),
        outputs: $result,
        activeCount: ([ $result[] | select(.enabled) ] | length),
        internalCount: ([ $result[] | select(.internal) ] | length),
        externalCount: ([ $result[] | select(.internal | not) ] | length)
      }
  ' <<<"$monitors"
}

display_status_json() {
  local snapshot pending profile_available now

  display_profiles_init
  snapshot="$(display_snapshot_json)" || return
  profile_available="$(
    jq -c --arg topology "$(jq -r '.topology' <<<"$snapshot")" \
      'any(.profiles[]; .topology == $topology)' "$display_profiles_file"
  )"
  now="$(date +%s)"
  if [ -r "$display_pending_file" ] && jq -e '.token | strings' "$display_pending_file" >/dev/null 2>&1; then
    pending="$(jq -c --argjson now "$now" '{token, expiresIn: ([0, (.deadline - $now)] | max)}' "$display_pending_file")"
  else
    pending=null
  fi

  jq -nce \
    --argjson snapshot "$snapshot" \
    --argjson profileAvailable "$profile_available" \
    --argjson pending "$pending" \
    '$snapshot + {profileAvailable: $profileAvailable, pending: $pending}'
}

display_layout_from_request() {
  local snapshot="$1"
  local request="$2"

  jq -nce --argjson snapshot "$snapshot" --argjson request "$request" '
    def fail($message): error($message);
    def mode_resolution:
      capture("^(?<width>[0-9]+)x(?<height>[0-9]+)@").width + "x" +
      capture("^(?<width>[0-9]+)x(?<height>[0-9]+)@").height;
    def preferred_mode:
      if .enabled and .width > 0 and .height > 0 then .mode
      else (.availableModes[0] // "preferred")
      end;
    def output_named($name):
      [ $snapshot.outputs[] | select(.name == $name) ][0];
    def common_resolution:
      [ $snapshot.outputs[] | [ .availableModes[]? | mode_resolution ] | unique ] as $sets
      | if ($sets | length) < 2 then null
        else reduce $sets[1:][] as $set ($sets[0]; [ .[] | select(. as $candidate | $set | index($candidate)) ])
        | map(. as $resolution | {
            resolution: $resolution,
            pixels: (($resolution | split("x")[0] | tonumber) * ($resolution | split("x")[1] | tonumber))
          })
        | sort_by(.pixels)
        | last
        | .resolution
        end;
    def best_mode($output; $resolution):
      [
        $output.availableModes[]?
        | select(startswith($resolution + "@"))
        | { mode: ., refresh: (capture("@(?<refresh>[0-9.]+)").refresh | tonumber) }
      ] | max_by(.refresh).mode;

    ($request.preset // "") as $preset
    | if (["extend", "duplicate", "internal", "external", "custom"] | index($preset)) == null
      then fail("unknown display preset") else . end
    | if ($snapshot.outputs | length) == 0 then fail("no connected displays") else . end
    | ($request.primary // ([ $snapshot.outputs[] | select(.focused) | .name ][0]) // ([ $snapshot.outputs[] | select(.enabled) | .name ][0]) // $snapshot.outputs[0].name) as $candidate
    | if output_named($candidate) == null then fail("selected main display is not connected") else . end
    | if $preset == "internal" and $snapshot.internalCount == 0 then fail("no internal display is connected")
      elif $preset == "external" and $snapshot.externalCount == 0 then fail("no external display is connected")
      elif $preset == "duplicate" and ($snapshot.outputs | length) < 2 then fail("duplicate mode needs at least two displays")
      else . end
    | (if $preset == "internal" and (output_named($candidate).internal | not) then
         [ $snapshot.outputs[] | select(.internal) | .name ][0]
       elif $preset == "external" and output_named($candidate).internal then
         [ $snapshot.outputs[] | select(.internal | not) | .name ][0]
       else $candidate end) as $primary
    | if $preset == "duplicate" then common_resolution else null end as $common
    | if $preset == "duplicate" and $common == null then fail("the connected displays have no common resolution") else . end
    | [
        $snapshot.outputs[]
        | . as $output
        | ($request.changes[$output.name] // {}) as $change
        | if $preset == "extend" then
            . + {
              enabled: true,
              mode: preferred_mode,
              position: (if .name == $primary then "0x0" else "auto-right" end),
              mirror: ""
            }
          elif $preset == "duplicate" then
            . + {
              enabled: true,
              mode: best_mode($output; $common),
              position: "0x0",
              scale: (output_named($primary).scale),
              mirror: (if .name == $primary then "" else $primary end)
            }
          elif $preset == "internal" then
            . + {
              enabled: .internal,
              mode: preferred_mode,
              position: (if .internal then (if .name == $primary then "0x0" else "auto-right" end) else .position end),
              mirror: ""
            }
          elif $preset == "external" then
            . + {
              enabled: (.internal | not),
              mode: preferred_mode,
              position: (if (.internal | not) then (if .name == $primary then "0x0" else "auto-right" end) else .position end),
              mirror: ""
            }
          else
            . + {
              mode: ($change.mode // .mode),
              scale: ($change.scale // .scale),
              position: (if .name == $primary then "0x0" elif .enabled then "auto-right" else .position end),
              mirror: ""
            }
          end
      ]
    | if ([ .[] | select(.enabled) ] | length) == 0 then fail("a display layout must keep at least one output enabled") else . end
    | if any(.[]; (.scale | type) != "number" or .scale < 0.5 or .scale > 4) then fail("display scale must be between 0.5 and 4") else . end
    | if any(.[]; . as $output | $output.enabled and $output.mode != "preferred" and
        (($output.availableModes | length) > 0) and
        (($output.availableModes | index($output.mode)) == null))
      then fail("invalid display mode") else . end
    | {
        topology: $snapshot.topology,
        primary: $primary,
        outputs: map({name, identity, enabled, mode, position, scale, mirror})
      }
  '
}

display_lua_string() {
  jq -Rr '@json' <<<"$1"
}

display_apply_layout() {
  local layout="$1"
  local lua=""
  local output name enabled mode position scale mirror primary

  while IFS= read -r output; do
    name="$(jq -r '.name' <<<"$output")"
    enabled="$(jq -r '.enabled' <<<"$output")"
    mirror="$(jq -r '.mirror' <<<"$output")"
    if [ "$enabled" = true ]; then
      mode="$(jq -r '.mode' <<<"$output")"
      position="$(jq -r '.position' <<<"$output")"
      scale="$(jq -r '.scale' <<<"$output")"
      lua="$lua hl.monitor({ output = $(display_lua_string "$name"), disabled = false, mode = $(display_lua_string "$mode"), position = $(display_lua_string "$position"), scale = $scale, mirror = $(display_lua_string "$mirror") });"
    else
      lua="$lua hl.monitor({ output = $(display_lua_string "$name"), disabled = true, mirror = "" });"
    fi
  done < <(jq -c '.outputs[]' <<<"$layout")

  ensure_hypr_env
  hyprctl eval "$lua" || return

  primary="$(jq -r '.primary // empty' <<<"$layout")"
  if [ -n "$primary" ]; then
    hyprctl dispatch "hl.dsp.focus({ monitor = $(display_lua_string "$primary") })" >/dev/null 2>&1 || true
  fi
}

display_profile_from_layout() {
  local layout="$1"

  jq -ce '
    . as $layout
    | {
        topology,
        primaryIdentity: ([ $layout.outputs[] | select(.name == $layout.primary) | .identity ][0] // ""),
        outputs: [
          $layout.outputs[]
          | . as $output
          | {
              identity,
              enabled,
              mode,
              position,
              scale,
              mirrorIdentity: ([ $layout.outputs[] | select(.name == $output.mirror) | .identity ][0] // "")
            }
        ]
      }
  ' <<<"$layout"
}

display_layout_from_profile() {
  local snapshot="$1"
  local profile="$2"

  jq -nce --argjson snapshot "$snapshot" --argjson profile "$profile" '
    def name_for($identity): ([ $snapshot.outputs[] | select(.identity == $identity) | .name ][0] // "");
    if $snapshot.topology != $profile.topology then error("display profile does not match the connected outputs") else . end
    | {
        topology: $snapshot.topology,
        primary: name_for($profile.primaryIdentity),
        outputs: [
          $profile.outputs[]
          | . as $saved
          | ($snapshot.outputs[] | select(.identity == $saved.identity))
          | {
              name,
              identity,
              enabled: $saved.enabled,
              mode: $saved.mode,
              position: $saved.position,
              scale: $saved.scale,
              mirror: name_for($saved.mirrorIdentity)
            }
        ]
      }
    | if (.outputs | length) != ($snapshot.outputs | length) then error("display profile is missing a connected output") else . end
    | if .primary == "" then .primary = ([ .outputs[] | select(.enabled) | .name ][0] // "") else . end
  '
}

display_cancel_rollback_unit() {
  local token="$1"
  local unit="desktop-shell-display-rollback-$token"

  systemctl --user stop "$unit.timer" >/dev/null 2>&1 || true
  systemctl --user reset-failed "$unit.service" >/dev/null 2>&1 || true
}

display_rollback_locked() {
  local token="$1"
  local pending before

  [ -r "$display_pending_file" ] || return 0
  pending="$(jq -ce --arg token "$token" 'select(.token == $token)' "$display_pending_file")" || return 0
  before="$(jq -ce '.before' <<<"$pending")"
  display_apply_layout "$before" >/dev/null
  rm -f "$display_pending_file"
  display_cancel_rollback_unit "$token"
}

display_rollback() (
  exec 9>"$display_lock_file"
  flock 9
  display_rollback_locked "$1"
)

display_apply_request() (
  local request="$1"
  local snapshot before layout token pending_tmp unit deadline

  jq -e 'type == "object"' <<<"$request" >/dev/null || {
    printf 'desktop-shell: display request must be a JSON object\n' >&2
    return 2
  }

  exec 9>"$display_lock_file"
  flock 9

  if [ -r "$display_pending_file" ]; then
    display_rollback_locked "$(jq -r '.token // empty' "$display_pending_file")"
  fi

  snapshot="$(display_snapshot_json)" || return
  before="$(jq -ce '{topology, primary: ([.outputs[] | select(.focused) | .name][0] // [.outputs[] | select(.enabled) | .name][0] // ""), outputs: [.outputs[] | {name, identity, enabled, mode, position, scale, mirror}]}' <<<"$snapshot")"
  layout="$(display_layout_from_request "$snapshot" "$request")" || return
  token="$$-$(date +%s%N)"
  unit="desktop-shell-display-rollback-$token"
  deadline="$(($(date +%s) + display_confirm_seconds))"

  pending_tmp="$(mktemp "$display_runtime_dir/.display-pending.XXXXXX")"
  jq -nce \
    --arg token "$token" \
    --argjson expiresIn "$display_confirm_seconds" \
    --argjson deadline "$deadline" \
    --argjson before "$before" \
    --argjson desired "$layout" \
    '{token: $token, expiresIn: $expiresIn, deadline: $deadline, before: $before, desired: $desired}' >"$pending_tmp"
  mv -f "$pending_tmp" "$display_pending_file"

  if ! systemd-run --user --quiet --collect --unit "$unit" --on-active="${display_confirm_seconds}s" \
    "$desktop_shell_executable" display rollback "$token"; then
    rm -f "$display_pending_file"
    printf 'desktop-shell: could not arm display rollback timer\n' >&2
    return 1
  fi

  if ! display_apply_layout "$layout" >/dev/null; then
    display_rollback_locked "$token"
    return 1
  fi

  jq -ce '{token, expiresIn}' "$display_pending_file"
)

display_keep() (
  local token="$1"
  local pending desired snapshot resolved profile profiles_tmp

  exec 9>"$display_lock_file"
  flock 9

  pending="$(jq -ce --arg token "$token" 'select(.token == $token)' "$display_pending_file" 2>/dev/null)" || {
    printf 'desktop-shell: display confirmation expired\n' >&2
    return 1
  }
  desired="$(jq -ce '.desired' <<<"$pending")"
  snapshot="$(display_snapshot_json)" || return
  resolved="$(
    jq -nce --argjson desired "$desired" --argjson snapshot "$snapshot" '
      {
        topology: $desired.topology,
        primary: $desired.primary,
        outputs: [
          $desired.outputs[]
          | . as $requested
          | ($snapshot.outputs[] | select(.identity == $requested.identity)) as $actual
          | $requested + {
              position: (if $requested.position == "auto-right" then $actual.position else $requested.position end)
            }
        ]
      }
    '
  )"
  profile="$(display_profile_from_layout "$resolved")"
  display_profiles_init
  profiles_tmp="$(mktemp "$display_state_dir/.profiles.XXXXXX")"
  jq -ce --argjson profile "$profile" '
    .profiles = ([.profiles[] | select(.topology != $profile.topology)] + [$profile])
  ' "$display_profiles_file" >"$profiles_tmp"
  mv -f "$profiles_tmp" "$display_profiles_file"
  rm -f "$display_pending_file"
  display_cancel_rollback_unit "$token"
)

display_restore_profile() (
  local snapshot topology profile layout token deadline now

  exec 9>"$display_lock_file"
  flock 9
  if [ -r "$display_pending_file" ]; then
    token="$(jq -r '.token // empty' "$display_pending_file")"
    deadline="$(jq -r '.deadline // 0' "$display_pending_file")"
    now="$(date +%s)"
    if [ -n "$token" ] && [ "$deadline" -le "$now" ] 2>/dev/null; then
      display_rollback_locked "$token"
    else
      return 0
    fi
  fi
  display_profiles_init
  snapshot="$(display_snapshot_json)" || return
  topology="$(jq -r '.topology' <<<"$snapshot")"
  profile="$(jq -ce --arg topology "$topology" '.profiles[] | select(.topology == $topology)' "$display_profiles_file")" || return 0
  layout="$(display_layout_from_profile "$snapshot" "$profile")" || return
  display_apply_layout "$layout" >/dev/null
)

display_reset() (
  local token

  exec 9>"$display_lock_file"
  flock 9
  if [ -r "$display_pending_file" ]; then
    token="$(jq -r '.token // empty' "$display_pending_file")"
    display_rollback_locked "$token"
  fi
  printf '%s\n' '{"version":1,"profiles":[]}' >"$display_profiles_file"
  ensure_hypr_env
  hyprctl reload >/dev/null
)
