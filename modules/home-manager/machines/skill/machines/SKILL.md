---
name: machines
description: Erik's machines, how they connect, and how much load each can take. Load before anything resource-heavy (running several agents, codex/claude sessions or jobs in parallel, batch generation, builds, test suites, local models, big downloads, anything with `&`, `xargs -P` or a worker pool), and whenever a task needs another machine (ssh, the homelab, the build server, the laptop).
---

# Erik's machines

| Machine | What it is | Reach it |
|---|---|---|
| **pc** | Erik's desktop: Ryzen 7 7800X3D, 16 threads, 30 GB RAM, RX 7900 XT 20 GB. LAN `192.168.50.232`. Runs Hyprland, his browsers, T3 Code (port 3773) and every agent session. | You are usually on it |
| **framework** | Erik's laptop, NixOS. Often asleep, off or away. | `ssh framework` (through the Proxmox Tailscale node; fails when asleep) |
| **proxmox** | Hypervisor, i7-6700K, 8 threads, 62 GB RAM. Runs the Tailscale subnet router for `192.168.50.0/24`. | `ssh proxmox` (root) |
| **naiaclaw** | VM 200 on proxmox: the k3s node for the homelab, 8 threads, 58 GB RAM. VIP `192.168.50.100`. | `ssh naiaclaw`, then `sudo kubectl ...` |
| **nix-builder** | A pod on naiaclaw: Nix build server and binary cache (`https://nix-cache.erikfrankling.duckdns.org`). | `ssh nix-builder`; builds with `nix build --store ssh-ng://root@192.168.50.100:2222` |

- Erik's phone and the laptop away from home reach the LAN over Tailscale.
- The homelab is configured in the homelab repo (`~/projects/personal/homelab`) and applied by Flux. The NixOS machines are configured in `~/.dotfiles`.
- Do not start VM 100 on proxmox (its address collides with the k3s VIP). Never reboot or power off any machine.

## Do not overload the pc

The pc is the machine Erik is sitting at. When it runs out of memory it does
not crash, it swaps. The desktop freezes and T3 Code stops answering. That
includes on his phone, and it includes the session you are running in.

### Heavy work runs on the homelab (Erik, 2026-10-21)

The pc is for Erik plus light agent work: editing, chat, git, small commands
and short checks. Anything long-running or CPU/disk/memory heavy runs on the
homelab, even though it is slower there:

| Work | How |
|---|---|
| Anything heavy in a repo (Gradle/APK builds, test suites, typechecks of big monorepos, embeddings and ML batch jobs, data processing, compiles) | `heavy -- <cmd>`: syncs the repo to the homelab worker and runs it there; `heavy pull <path>` brings results back |
| Android emulator | `heavy emulator start` (KVM on the homelab, adb forwarded to the pc); `heavy emulator stop` when done |
| Nix builds and NixOS evaluations | `rebuild` (evaluates and builds on the builder, activates here), `nix-remote build/eval ...`; uncached builds go to the builder by themselves |

Never start an emulator, a Gradle/NDK build, llama-server or another model
server, a long test run or a NixOS evaluation on the pc. Never run them on
the pc "because the homelab is slow"; Erik explicitly prefers slow.

### Enforcement on the pc (`modules/nixos/agent-priority`)

Every T3 Code agent session (claude, codex, opencode, grok, cursor) and all it
spawns runs under `app-t3code.slice`:

- **CPU idle class**, and **disk caps** (150 MB/s read, 60 MB/s write): the
  disk is a DRAM-less NV3 that stalls every reader when something writes flat
  out.
- **Memory:** all agents together are throttled above 9 GB and killed above
  11 GB of RAM, with at most 2 GB of swap. There is no disk swap, only zram.
  systemd-oomd kills the agent scope that thrashes hardest. T3 then reports
  the session as killed for memory: move the work to the homelab, do not
  retry it here.
- **`systemd-run --user` stays inside** the slice (a wrapper adds
  `--slice-inherit --nice=10` and makes the job the first OOM victim). Do not
  escape with `--slice=`, Docker, sudo or system units. Docker containers
  are capped per container anyway.
- **`nix` refuses local NixOS evaluations** from an agent: `nix build/eval`
  of `nixosConfigurations`/`homeConfigurations` goes to the builder
  (`nix-remote`) by itself, and `nix repl`/`develop` on them is refused.
- **lag-guard** watches the pc's disk and memory pressure. When it stays high
  it kills agent work, in this order: emulators; local Nix builds and big
  `nix` evaluations; compilers, Gradle, llama-server, typecheckers, any agent
  process over 1.5 GB and every unit an agent started with systemd-run. It
  notifies Erik with what it stopped.

### Light-work rules on the pc

- Cap parallelism for whatever small work remains (`-j4`, `xargs -P 4`).
- One typecheck or test run at a time per session, and only small ones.
- Clean up: no background dev servers, browsers or models left running.

This has happened: on 2026-10-16 an agent started about 28 `codex exec` image
jobs at once (20 backgrounded with `&`, 8 more through `xargs -P 8`). They
took 16 GB of RAM and 13 GB of swap, and T3 Code stopped answering for 5
minutes.

Before starting anything that runs in parallel or uses a lot of memory:

1. **Estimate the cost.** One agent session (`codex exec`, `claude`) with its
   MCP servers takes roughly 0.5–1 GB. A browser, a Nix evaluation of a
   NixOS system or a big test run can each take several GB. Multiply by how
   many will run at once.
2. **Check what is free:** `free -g`, and `cat /proc/pressure/memory`
   (anything above a few percent under `full` means it is already swapping).
   Erik's browsers and apps normally use 10–15 GB on their own.
3. **Cap parallelism.** Keep the total new load to about 2 GB on the pc:
   `xargs -P 4`, a worker pool, or batches, never one `&` per item over a
   long list. Start small, watch `free -g`, then scale up if there is room.
4. **Move heavy work off the pc**: `heavy -- <cmd>` for jobs, `rebuild` and
   `nix-remote` for Nix, and long-running services belong in the homelab. Local LLMs must fit fully in
   GPU memory (see `~/.dotfiles/AGENTS.md`).
5. **Clean up.** Do not leave background jobs, dev servers or loaded models
   running when you are done.

If the pc is already slow (`uptime` load far above 16, or high memory
pressure), do not add to it. Wait, or stop your own jobs first.
