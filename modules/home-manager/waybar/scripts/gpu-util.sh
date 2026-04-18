#!/usr/bin/env bash
# GPU utilization for waybar

set -eo pipefail

util=$(rocm-smi -u --json 2>/dev/null | jq -r '.card0["GPU use (%)"] // "0"')

echo "{\"text\": \"󰾲 ${util}%\"}"
