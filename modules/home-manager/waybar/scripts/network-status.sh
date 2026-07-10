#!/usr/bin/env bash
# Compact network status for Waybar.
# Priority: VPN tunnel, wired Ethernet, Wi-Fi SSID, disconnected.

set -euo pipefail

json() {
  jq -cn --arg text "$1" --arg tooltip "$2" '{text: $text, tooltip: $tooltip}'
}

if ip link show tun0 up >/dev/null 2>&1; then
  json " tun0" "VPN: tun0"
  exit 0
fi

if nmcli --terse --fields TYPE,STATE device status 2>/dev/null | grep -q '^ethernet:connected$'; then
  json " eth" "Ethernet connected"
  exit 0
fi

ssid="$(nmcli --terse --escape no --fields active,ssid device wifi 2>/dev/null | awk -F: '$1 == "yes" { print $2; exit }')"
if [[ -n "$ssid" ]]; then
  json " ${ssid}" "Wi-Fi: ${ssid}"
  exit 0
fi

json "⚠  Disconnected" "Network disconnected"
