#!/usr/bin/env bash
# VRAM usage for waybar

set -eo pipefail

vram_raw=$(rocm-smi --showmeminfo vram 2>/dev/null)
vram_total=$(echo "$vram_raw" | grep 'GPU\[0\]' | grep 'Total Memory' | awk '{print $NF}' | tr -d '()B:')
vram_used=$(echo "$vram_raw" | grep 'GPU\[0\]' | grep 'Used Memory' | awk '{print $NF}' | tr -d '()B:')

vram_used=${vram_used:-0}
vram_total=${vram_total:-1}

vram_used_gb=$(awk "BEGIN {printf \"%.1f\", $vram_used / 1073741824}")
vram_total_gb=$(awk "BEGIN {printf \"%.1f\", $vram_total / 1073741824}")

echo "{\"text\": \"󰘚 ${vram_used_gb}/${vram_total_gb}GB\"}"
