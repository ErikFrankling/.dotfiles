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

### The agent slice (2026-10-21)

Every T3 Code agent session (claude, codex, opencode, grok, cursor) and all
it spawns runs under `app-t3code.slice` (`modules/nixos/agent-priority.nix`):

- **CPU idle class:** you get only the CPU Erik's apps leave unused. A
  parallel build is not slow because the pc is weak; it waits behind him.
- **Memory:** all agents together are throttled above 12 GB and killed above
  15 GB of RAM, with at most 6 GB in swap. systemd-oomd kills the agent scope
  that thrashes hardest (30 s above 50 % memory pressure). T3 then reports the
  session as killed for memory: run less at once, do not just retry.
- **`systemd-run --user` stays inside.** From an agent, `systemd-run` is a
  wrapper that adds `--slice-inherit --nice=10` and makes the job the first OOM
  victim. Do not pass `--slice=` to escape it, and do not move heavy work into
  Docker, sudo or system units to get around the limits.

### Heavy work rules

- **Nix builds:** anything not in a cache is built on the homelab builder
  (`nix.buildMachines`, slower but off the desktop). Check
  `nix build --dry-run` first; a real compile in the list is a cache miss to
  fix, not to wait out (`~/.dotfiles/AGENTS.md`). Do not run several NixOS
  evaluations or rebuilds at once: each evaluation takes several GB.
- **Native/Gradle builds:** cap parallelism (`--max-workers=4`,
  `CMAKE_BUILD_PARALLEL_LEVEL=4`, `make -j4`, `NINJAFLAGS=-j4`). An Android
  release APK comes from CI (`.github/workflows/erik-android.yml`) whenever
  that is enough; build locally only to test something CI cannot.
- **Android emulators:** at most one on the pc, across all agents. Check
  `pgrep -fa qemu-system` before starting one and reuse a running one instead
  of starting a second. Kill it (`adb emu kill`) as soon as you are done, and
  never leave one idle between tasks.
- **Typecheckers, test suites, browsers:** one at a time per session. A
  `tsgo`/`tsc` run of the T3 Code monorepo takes about 3.5 GB.

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
3. **Cap parallelism.** Keep the total new load to about 8 GB on the pc:
   `xargs -P 4`, a worker pool, or batches, never one `&` per item over a
   long list. Start small, watch `free -g`, then scale up if there is room.
4. **Move heavy work off the pc** when the homelab can do it: Nix builds go
   to the build server (`nix-nightly build`, or `--store ssh-ng://...`), and
   long-running services belong in the homelab. Local LLMs must fit fully in
   GPU memory (see `~/.dotfiles/AGENTS.md`).
5. **Clean up.** Do not leave background jobs, dev servers or loaded models
   running when you are done.

If the pc is already slow (`uptime` load far above 16, or high memory
pressure), do not add to it. Wait, or stop your own jobs first.
