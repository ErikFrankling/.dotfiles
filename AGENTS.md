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

## Understanding the Config

Nix is very hard for LLMs — patterns and idioms vary widely. When unsure or starting a new task, read existing files in this config to understand how things are structured.

### Good Files to Read First

| File                                        | Why                                               |
| ------------------------------------------- | ------------------------------------------------- |
| `flake.nix`                                 | Shows inputs, outputs, specialArgs, multiple pkgs |
| `hosts/pc/configuration.nix`                | Host config pattern with imports                  |
| `modules/nixos/default.nix`                 | How shared modules are imported                   |
| `modules/home-manager/hyprland/options.nix` | Example of `mkOption` definitions                 |
| `hosts/pc/home.nix`                         | Home-manager module structure                     |

### Common Patterns

#### Module with enable option:

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

#### Host imports with disabled modules:

```nix
imports = [
  ../../modules/nixos/desktop.nix
  # ../../modules/nixos/ollama.nix    # Was using this before, disabled for now
  # ../../modules/nixos/vm-host.nix   # Tried this, didn't work
];
```

#### Passing special args through layers:

```nix
# In flake.nix
specialArgs = {
  inherit inputs username otherPkgs;
};

# In host config
home-manager = {
  extraSpecialArgs = {
    inherit inputs username otherPkgs;
  };
};
```

#### Using multiple nixpkgs:

```nix
{ otherPkgs, ... }:
{
  environment.systemPackages = [
    otherPkgs.pkgsStable.somePackage
    otherPkgs.pkgsMaster.anotherPackage
  ];
}
```

---

## Git Protocol

**NEVER commit, push, or pull unless explicitly told to do so.**

- Only commit when the user explicitly asks you to
- Never push to remote unless explicitly instructed
- Never pull or fetch unless explicitly instructed
- If you're unsure, ask first

This is critical — the user wants full control over when changes are committed and synchronized.

---

## Temporary Files

- **Create temp files in the working directory** — never in `/tmp`
- **Always delete temp files when the task is done**
- Examples of acceptable temp files:
  - Test scripts
  - Command output files (e.g., `cat somefile > output.txt`)
- Clean up after use

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

#### 2. Host Configuration (hosts/\*/configuration.nix)

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

---

## Local LLM System Overview

### The Problem

The local LLM server runs on a desktop shared with Hyprland (the compositor). GPU VRAM is a shared resource — if the LLM uses too much VRAM, it will conflict with Hyprland and crash the entire system.

### Hardware

- **GPU**: AMD RX 7900 XT (20GB VRAM actual)
- **Safe VRAM budget**: ~15-16GB for model weights (leaves ~4-5GB for Hyprland)

---

## VRAM Testing Methodology

### The Approach

1. **Start conservative**: Always begin with 4096 context to verify model loads without crashing
2. **Test with simple request**: Send a minimal request (`hi`) to trigger model initialization
3. **Check VRAM after first request**: Once a model has successfully served a request, VRAM becomes very stable
4. **Increase context gradually**: If VRAM is at ~19.6-19.8GB used with 0.2-0.4GB free, the system is stable - you can try higher contexts
5. **Watch for the crash threshold**: If VRAM hits ~19.9GB with almost no free space, the next context increase will likely crash Hyprland

### The VRAM Script

Use `/home/erikf/.dotfiles/bin/vram-check` for quick VRAM readings in GB:

```bash
/home/erikf/.dotfiles/bin/vram-check
# Output: VRAM: 19.6GB / 20.0GB (0.4GB free)
```

This is easier to read than raw `rocm-smi` output.

### Key Insight

**Once a model serves a request successfully, VRAM usage stabilizes.** The goal is to find the maximum context where:

- VRAM used is ~19.6-19.8GB
- Free space is ~0.2-0.4GB
- System runs for hours without crashing

If you push too far (e.g., 19.9GB used, 0.0GB free), Hyprland will crash on the next model load or request.

### Example: Finding the limit

| Model | Quant  | Size   | 128k VRAM | 192k VRAM | 256k VRAM        |
| ----- | ------ | ------ | --------- | --------- | ---------------- |
| Opus  | IQ4_XS | 14.7GB | 15.1GB    | 19.7GB    | 19.9GB (crashed) |

- 192k context with 19.7GB used (0.3GB free) is stable
- 256k context with 19.9GB used (0.0GB free) crashed Hyprland

---

## Workflow: Adding or Modifying Models

Follow this checklist **every time** to avoid crashing the system:

### Step 1: Choose Model Size

- Check model weights size on HuggingFace
- Target: **~15-16 GB** quantization
- Examples:
  - Qwen3.5-27B IQ4_NL = 14.6GB ✓ (safe)
  - Qwen3.5-27B Q4_K_M = 16.5GB ✓ (safe but tight to fit large ctx)
  - Qwen3.5-35B-A3B UD-IQ4_NL = 17.8GB ✓ (very tight for big ctx moe has no effect on vram useage still a lot of vram)

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

**Key insight**: Once a model has successfully served a request, VRAM usage becomes very stable. The goal is to maximize context while keeping VRAM tight (~19.8GB used, ~0.2GB free) without crashing.

- **Safe**: Used VRAM ≤ 18GB (~3GB+ free for Hyprland)
- **At Risk**: Used VRAM 18-19GB (tight, monitor closely)
- **Target**: Used VRAM ~19.8GB with ~0.2GB free (maximum utilization, stable)
- **Crash Risk**: Used VRAM > 19.9GB (will conflict with Hyprland)

**Testing approach**:

1. Start with 4096 context (uses less VRAM)
2. Test with a simple request (`hi`)
3. Check VRAM after model loads and request completes
4. If stable (~19.8GB used), increase context in steps
5. Goal: stretch context as far as possible without crashing

### Step 6: Only If Safe - Increase Context

If VRAM is safe (~15-16GB used), you can:

1. Update config to use `-c 131072` (128k context)
2. Rebuild and test again
3. Re-check VRAM

---

## Quick Reference

| Context | Approx KV Cache Overhead |
| ------- | ------------------------ |
| 4096    | ~1GB                     |
| 32768   | ~4GB                     |
| 65536   | ~8GB                     |
| 131072  | ~16GB                    |
| 192000  | ~17GB                    |
| 262144  | ~18GB                    |

---

## If System Crashes

1. Wait for GPU to cool down (memory clears on reboot)
2. On next boot, start with 4096 context
3. Check model size - may need smaller quantization
4. If problems persist, the model is too large for this GPU

---

## Hard Rule: Quantization

**Only use 4-bit or higher quantizations.** Never use 2-bit or 3-bit quants (IQ2, IQ3, etc.).

- Allowed: Q4_0, Q4_1, Q4_K_S, Q4_K_M, IQ4_NL, IQ4_XS, etc.
- Forbidden: IQ2_XXS, IQ2_XS, IQ2_S, IQ2_M, IQ3_XXS, IQ3_XS, IQ3_S, IQ3_M, etc.

This ensures quality is preserved. Even "Q4_K_S" or "IQ4_XS" (smaller 4-bit variants) are acceptable.

---

## Current Models (RX 7900 XT - 20GB VRAM)

All tested and working at 192k context:

| Model               | Quant               | Size   | VRAM @ 192k | Notes            |
| ------------------- | ------------------- | ------ | ----------- | ---------------- |
| Qwen3.5-27B         | IQ4_NL (Unsloth)    | 14.6GB | 19.6GB      | Base model       |
| Qwen3.5-27B Opus    | IQ4_XS (imatrix)    | 14.7GB | 19.7GB      | Claude distilled |
| Qwen3.5-35B-A3B MoE | UD-IQ4_NL (Unsloth) | 17.8GB | 19.0GB      | 3B active params |

**Context testing results:**

- 192k: ✓ stable for all models
- 256k: works but 19.9GB used (too tight, crashed Hyprland)
- 320k: crashed Hyprland

**VRAM target**: ~19.6-19.8GB used with 0.2-0.4GB free is optimal.

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

---

## Bash Commands

**NEVER run commands that may hang indefinitely.** This includes:

- Commands with backgrounding (`&`) that you need to check with `sleep` after
- Interactive commands or commands waiting for input
- Commands that start background processes you then try to terminate

If you need to run a background process, use `nohup ... &` with proper timeout, or avoid checking the result.
