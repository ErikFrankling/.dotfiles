#!/usr/bin/env bash
# Swap usage and swap activity for Waybar.
#
# "usage" shows allocated swap.
# "activity" shows current RAM<->swap churn.
#
# /proc/vmstat pswpin/pswpout are cumulative page counters since boot.
# Sampling their delta between Waybar ticks shows current swap churn:
#   rate = (delta pages * page size) / elapsed seconds

set -euo pipefail

mode="${1:-usage}"

print_usage() {
  awk '
    /^SwapTotal:/ { total = $2 }
    /^SwapFree:/ { free = $2 }
    END {
      used = total - free
      percent = total > 0 ? used * 100 / total : 0
      used_gb = used / 1024 / 1024
      total_gb = total / 1024 / 1024

      if (percent >= 95) {
        state = "critical"
      } else if (percent >= 90) {
        state = "warning"
      } else {
        state = ""
      }

      printf "{\"text\":\"  %.1f/%.1fGB\",\"tooltip\":\"Swap used: %.1f/%.1fGB (%.0f%%)\",\"class\":\"%s\",\"percentage\":%.0f}\n",
        used_gb, total_gb, used_gb, total_gb, percent, state, percent
    }
  ' /proc/meminfo
}

print_activity() {
  local state_dir state_file now page_size pswpin pswpout
  local prev_now prev_pswpin prev_pswpout

  state_dir="${XDG_RUNTIME_DIR:-/tmp}"
  state_file="${state_dir}/waybar-swap-activity-${UID:-$(id -u)}"
  now="$(date +%s)"
  page_size="$(getconf PAGESIZE)"

  read -r pswpin pswpout < <(
    awk '
      $1 == "pswpin" { in_pages = $2 }
      $1 == "pswpout" { out_pages = $2 }
      END { print in_pages + 0, out_pages + 0 }
    ' /proc/vmstat
  )

  prev_now="$now"
  prev_pswpin="$pswpin"
  prev_pswpout="$pswpout"

  if [[ -r "$state_file" ]]; then
    read -r prev_now prev_pswpin prev_pswpout <"$state_file" || true
  fi

  printf '%s %s %s\n' "$now" "$pswpin" "$pswpout" >"$state_file"

  awk \
    -v pswpin="$pswpin" \
    -v pswpout="$pswpout" \
    -v prev_pswpin="$prev_pswpin" \
    -v prev_pswpout="$prev_pswpout" \
    -v now="$now" \
    -v prev_now="$prev_now" \
    -v page_size="$page_size" '
    BEGIN {
      elapsed = now - prev_now
      if (elapsed < 1) {
        elapsed = 1
      }

      in_delta = pswpin - prev_pswpin
      out_delta = pswpout - prev_pswpout
      if (in_delta < 0) {
        in_delta = 0
      }
      if (out_delta < 0) {
        out_delta = 0
      }

      in_mib_s = in_delta * page_size / elapsed / 1024 / 1024
      out_mib_s = out_delta * page_size / elapsed / 1024 / 1024
      total_mib_s = in_mib_s + out_mib_s

      if (total_mib_s >= 128) {
        state = "critical"
      } else if (total_mib_s >= 32) {
        state = "warning"
      } else {
        state = ""
      }

      printf "{\"text\":\"⇄ %.0fMiB/s\",\"tooltip\":\"RAM ⇄ swap activity: %.1fMiB/s\\nSwap in: %.1fMiB/s\\nSwap out: %.1fMiB/s\\nThresholds: warning ≥32MiB/s, critical ≥128MiB/s\",\"class\":\"%s\",\"percentage\":%.0f}\n",
        total_mib_s, total_mib_s, in_mib_s, out_mib_s, state, total_mib_s
    }
  '
}

case "$mode" in
  usage)
    print_usage
    ;;
  activity)
    print_activity
    ;;
  *)
    echo "usage: $0 [usage|activity]" >&2
    exit 2
    ;;
esac
