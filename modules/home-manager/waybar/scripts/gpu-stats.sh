#!/usr/bin/env bash
# Waybar GPU stats module for AMD GPUs via ROCm

set -eo pipefail

# Get GPU utilization for card0 (main GPU)
util=$(rocm-smi -u --json 2>/dev/null | jq -r '.card0["GPU use (%)"] // "0"')

# Get VRAM info for GPU0
vram_raw=$(rocm-smi --showmeminfo vram 2>/dev/null)

# Extract total and used - need to handle the multiline output carefully
# Line with "Total Memory" and line with "Used Memory"
vram_total=$(echo "$vram_raw" | grep 'GPU\[0\]' | grep 'Total Memory' | awk '{print $NF}' | tr -d '()B:')
vram_used=$(echo "$vram_raw" | grep 'GPU\[0\]' | grep 'Used Memory' | awk '{print $NF}' | tr -d '()B:')

# Fallback if parsing fails
vram_used=${vram_used:-0}
vram_total=${vram_total:-1}

# Calculate percentage
vram_pct=$((vram_used * 100 / vram_total))

# Output JSON for waybar
echo "{\"text\": \"󰾲 ${util}% 󰘚 ${vram_pct}%\", \"tooltip\": \"GPU: ${util}% | VRAM: ${vram_pct}% (${vram_used}/${vram_total} B)\"}"
