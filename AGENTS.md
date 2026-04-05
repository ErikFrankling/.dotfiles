# AGENTS.md - Guidelines for NixOS Configuration

## Critical: This is a NixOS Configuration

**Everything must be done the Nix way.** This is a declarative NixOS configuration — no imperative steps allowed.

### Nix Best Practices

- **Always use Nix-native approaches** — If you're unsure how to do something in Nix, search online first.
- **LLMs hallucinate about Nix** — Nix has limited training data, so always double-check online.
- **Search before acting** — Use the web to find how Nix users solve problems. There likely already exists a declarative solution.
- **No imperative commands** — Avoid `systemctl enable`, `systemctl start`, `pip install`, etc. Use Nix options instead.
- **When in doubt, search** — If you don't know the Nix option for something, search for it.

---

## Rebuild Command

```shell
nh os switch /home/${username}/.dotfiles --hostname ${hostName}
```

---

## Local LLM System Overview

### The Problem
The local LLM server runs on a desktop shared with Hyprland (the compositor). GPU VRAM is a shared resource — if the LLM uses too much VRAM, it will conflict with Hyprland and crash the entire system.

### Hardware
- **GPU**: AMD RX 7900 XT (21GB VRAM total)
- **Safe VRAM budget**: ~15-16GB for model weights (leaves ~5-6GB for Hyprland)

---

## Workflow: Adding or Modifying Models

Follow this checklist **every time** to avoid crashing the system:

### Step 1: Choose Model Size
- Check model weights size on HuggingFace
- Target: **~15-16 GB** quantization
- Examples:
  - Qwen3.5-27B IQ4_NL = 14.6GB ✓ (safe)
  - Qwen3.5-27B Q4_K_M = 16.5GB ✓ (safe but tight)
  - Qwen3.5-35B-A3B UD-IQ4_NL = 17.8GB ✓ (safe for MoE with 3B active)

### Step 2: Prepare System
```bash
# Kill any running llama-servers first
pkill -f llama-server

# Check VRAM is free (should show ~3-4GB used by Hyprland only)
rocm-smi --showmeminfo vram
```

### Step 3: First Run - 4096 Context
- ALWAYS start with `-c 4096` in config
- This uses less VRAM for KV cache
- Do NOT use 128k on first run

### Step 4: Test and Verify
```bash
# Make request
curl -s -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "your-model", "messages": [{"role": "user", "content": "Hi"}], "max_tokens": 20}'

# Check VRAM after model loads
rocm-smi --showmeminfo vram
```

### Step 5: Evaluate VRAM Usage
- **Safe**: Used VRAM ≤ 18GB (~3GB+ free for Hyprland)
- **At Risk**: Used VRAM 18-19GB (tight, monitor closely)
- **Crash Risk**: Used VRAM > 19GB (will conflict with Hyprland)

### Step 6: Only If Safe - Increase Context
If VRAM is safe (~15-16GB used), you can:
1. Update config to use `-c 131072` (128k context)
2. Rebuild and test again
3. Re-check VRAM

---

## Quick Reference

| Context | Approx KV Cache Overhead |
|---------|-------------------------|
| 4096    | ~1GB                    |
| 32768   | ~4GB                    |
| 65536   | ~8GB                    |
| 131072  | ~16GB                   |

---

## If System Crashes

1. Wait for GPU to cool down (memory clears on reboot)
2. On next boot, start with 4096 context
3. Check model size - may need smaller quantization
4. If problems persist, the model is too large for this GPU

---

## Monitoring Commands

```bash
# Check VRAM usage
rocm-smi --showmeminfo vram

# Watch VRAM in real-time
watch -n 1 rocm-smi --showmeminfo vram

# Check running llama processes
pgrep -a llama
```