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

## Git Protocol

**NEVER commit, push, or pull unless explicitly told to do so.**

- Only commit when the user explicitly asks you to
- Never push to remote unless explicitly instructed
- Never pull or fetch unless explicitly instructed
- If you're unsure, ask first

This is critical — the user wants full control over when changes are committed and synchronized.

---

## NixOS Configuration Structure

### File Structure Overview

```
.dotfiles/
├── flake.nix                 # Main flake file, defines inputs and outputs
├── hosts/                    # Per-host configurations
│   ├── pc/                   # Desktop machine
│   │   ├── configuration.nix
│   │   ├── home.nix
│   │   └── hardware-configuration.nix
│   ├── framework/            # Laptop
│   ├── vm/                   # VM
│   └── wsl/                  # WSL
└── modules/
    ├── nixos/                # NixOS system modules
    │   ├── default.nix       # Imports all shared modules
    │   ├── secrets.nix       # SOPS age secrets
    │   ├── hyprland.nix
    │   ├── desktop.nix
    │   └── ...
    └── home-manager/         # Home-manager user modules
        ├── hyprland/
        │   ├── default.nix
        │   └── options.nix  # Custom options for host-specific overrides
        └── ...
```

### How It Works

#### 1. Flake Inputs (flake.nix)

The flake defines multiple nixpkgs instances:
- `nixpkgs` (nixos-unstable) — main/default
- `nixpkgs_master` — master branch
- `nixpkgs_stable` — release-25.05

These are passed to hosts via `otherPkgs` special arg.

#### 2. Host Configuration (hosts/*/configuration.nix)

Each host imports:
- Its own `hardware-configuration.nix` (from `nixos-generate-config`)
- The shared modules directory via `../../modules/nixos`
- Host-specific modules

Modules are imported and **left commented out when not in use**, not deleted. This preserves the history of how something was configured.

#### 3. Shared Modules (modules/nixos/default.nix)

This file imports all shared modules that apply to all hosts. It's the central hub.

#### 4. Per-Host Options

Options are exposed via `options.nix` files in module subdirectories (e.g., `modules/home-manager/hyprland/options.nix`). These define `mkOption` types that hosts can override.

**You don't need to expose options for everything** — only for things that differ between hosts. Many modules just work without options.

#### 5. Secrets Handling

Secrets use **SOPS with age**:
- Keys stored in `~/.config/sops/age/keys.txt` or SSH keys
- Secrets defined in `sops.secrets` attribute set
- Encrypted files live in `hosts/*/secrets/secrets.yaml`

Example from pc/configuration.nix:
```nix
sops.secrets.syncthing-cert = { };
sops.secrets.kth-password = {
  owner = username;
};
```

#### 6. Keeping Old Modules

**Never delete unused modules.** Keep them:
- Commented out in imports
- With options left commented (or with explanatory comments)

This lets you:
- Look back and see how you configured something before
- Re-enable things quickly without searching git history
- Understand the evolution of your setup

Example pattern:
```nix
imports = [
  ../../modules/nixos/desktop.nix
  # ../../modules/nixos/ollama.nix    # Was using this before, disabled for now
  # ../../modules/nixos/vm-host.nix   # Tried this, didn't work with my setup
];
```

#### 7. Multiple nixpkgs Instances

The flake creates three package sets:
- `pkgs` — nixos-unstable (default)
- `pkgsMaster` — master branch
- `pkgsStable` — release-25.05

Access in modules via `otherPkgs.pkgsMaster`, etc.

Example usage in a module:
```nix
{ otherPkgs, ... }:
{
  # Use stable for something specific
  environment.systemPackages = [ otherPkgs.pkgsStable.somePackage ];
}
```

### Module Patterns

#### Basic Module Structure
```nix
{ config, pkgs, lib, ... }:

{
  options = {
    myModule.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };
  };

  config = lib.mkIf config.myModule.enable {
    # module contents
  };
}
```

#### Importing into Host
```nix
# In hosts/pc/configuration.nix
imports = [
  ../../modules/nixos/some-module.nix
];
```

#### Overriding Options
```nix
# In hosts/pc/configuration.nix
myModule.enable = true;
someOption = "custom-value";
```

### Best Practices

1. **Never delete old modules** — comment them out instead
2. **Comment disabled options** — explain why something is disabled
3. **Use SOPS for secrets** — never commit plain secrets
4. **Keep hardware-configuration.nix** — generated by nixos-generate-config
5. **Test with `--dry-run`** before applying

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