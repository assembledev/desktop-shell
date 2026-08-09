#!/usr/bin/env bash

bluetooth_status_json() {
  controller_info="$(bluetoothctl show 2>/dev/null || true)"
  controller="$(
    printf '%s\n' "$controller_info" |
      awk '/^Controller [[:xdigit:]]{2}(:[[:xdigit:]]{2}){5}/ { print $2; exit }'
  )"

  if [ -n "$controller" ]; then
    available=true
  else
    available=false
  fi

  bluetooth_property() {
    property="$1"
    printf '%s\n' "$controller_info" |
      awk -v property="$property" '
        $1 == property ":" {
          sub(/^[^:]+:[[:space:]]*/, "");
          print;
          exit;
        }
      '
  }

  powered="$(bluetooth_property Powered)"
  discoverable="$(bluetooth_property Discoverable)"
  pairable="$(bluetooth_property Pairable)"
  discovering="$(bluetooth_property Discovering)"
  alias="$(bluetooth_property Alias)"

  jq -n \
    --argjson available "$available" \
    --argjson enabled "$([ "$powered" = yes ] && printf true || printf false)" \
    --argjson discoverable "$([ "$discoverable" = yes ] && printf true || printf false)" \
    --argjson pairable "$([ "$pairable" = yes ] && printf true || printf false)" \
    --argjson discovering "$([ "$discovering" = yes ] && printf true || printf false)" \
    --arg controller "$controller" \
    --arg alias "$alias" \
    '{
      available: $available,
      enabled: $enabled,
      discoverable: $discoverable,
      pairable: $pairable,
      discovering: $discovering,
      controller: $controller,
      alias: $alias
    }'
}

bluetooth_devices_json() {
  {
    bluetoothctl devices 2>/dev/null || true
    bluetoothctl devices Paired 2>/dev/null || true
    bluetoothctl devices Connected 2>/dev/null || true
  } |
    awk '
      $1 == "Device" && $2 ~ /^[[:xdigit:]]{2}(:[[:xdigit:]]{2}){5}$/ && !seen[$2]++ {
        print $2;
      }
    ' |
    while IFS= read -r address; do
      info="$(bluetoothctl info "$address" 2>/dev/null || true)"
      [ -n "$info" ] || continue

      bluetooth_device_property() {
        property="$1"
        printf '%s\n' "$info" |
          awk -v property="$property" '
            $1 == property ":" {
              sub(/^[^:]+:[[:space:]]*/, "");
              print;
              exit;
            }
          '
      }

      alias="$(bluetooth_device_property Alias)"
      [ -n "$alias" ] || alias="$(bluetooth_device_property Name)"
      [ -n "$alias" ] || alias="$address"
      icon="$(bluetooth_device_property Icon)"
      paired="$(bluetooth_device_property Paired)"
      trusted="$(bluetooth_device_property Trusted)"
      connected="$(bluetooth_device_property Connected)"
      rssi="$(
        printf '%s\n' "$info" |
          awk '
            /^[[:space:]]*RSSI:/ {
              if (match($0, /\((-?[0-9]+)\)/, value)) {
                print value[1];
              } else if (match($0, /RSSI:[[:space:]]*(-?[0-9]+)/, value)) {
                print value[1];
              }
              exit;
            }
          '
      )"
      battery="$(
        printf '%s\n' "$info" |
          awk '
            /Battery Percentage:/ {
              if (match($0, /\(([0-9]+)\)/, value)) {
                print value[1];
              } else if (match($0, /Battery Percentage:[[:space:]]*([0-9]+)/, value)) {
                print value[1];
              }
              exit;
            }
          '
      )"

      printf '%s\0%s\0%s\0%s\0%s\0%s\0%s\0%s\0' \
        "$address" \
        "$alias" \
        "$icon" \
        "$paired" \
        "$trusted" \
        "$connected" \
        "$rssi" \
        "$battery"
    done |
    jq -Rs '
      split("\u0000")[:-1] as $items
      | [range(0; $items | length; 8) as $i
          | ($items[$i + 6] | try tonumber catch null) as $rssi
          | {
              address: $items[$i],
              name: $items[$i + 1],
              icon: $items[$i + 2],
              paired: ($items[$i + 3] == "yes"),
              trusted: ($items[$i + 4] == "yes"),
              connected: ($items[$i + 5] == "yes"),
              rssi: $rssi,
              signal: (if $rssi == null then null else ([0, ([100, (($rssi + 100) * 2)] | min)] | max) end),
              battery: ($items[$i + 7] | try tonumber catch null)
            }]
      | sort_by((.connected | not), (.paired | not), (.name | ascii_downcase))
    '
}

bluetooth_require_address() {
  address="$1"
  if ! printf '%s\n' "$address" | grep -Eq '^[[:xdigit:]]{2}(:[[:xdigit:]]{2}){5}$'; then
    printf 'Invalid Bluetooth address\n' >&2
    return 2
  fi
}

bluetooth_set_adapter_property() {
  property="$1"
  value="$2"

  if ! timeout --signal=TERM --kill-after=0.2s 1s bluetoothctl "$property" "$value" >/dev/null; then
    printf 'desktop-shell: could not set Bluetooth %s %s\n' "$property" "$value" >&2
    return 1
  fi
}

bluetooth_private_mode() {
  bluetooth_set_adapter_property discoverable off
  bluetooth_set_adapter_property pairable off
}

bluetooth_pairing_mode() {
  bluetooth_set_adapter_property pairable on
  if ! bluetooth_set_adapter_property discoverable on; then
    bluetooth_set_adapter_property pairable off || true
    return 1
  fi
}

bluetooth_pairing_session() {
  bluetooth_pairing_session_cleanup() {
    trap - EXIT HUP INT TERM
    bluetooth_private_mode
  }

  trap bluetooth_pairing_session_cleanup EXIT
  trap 'exit 0' HUP INT TERM

  bluetooth_pairing_mode
  printf 'ready\n'

  while IFS= read -r request; do
    [ "$request" = close ] && break
  done
}
