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

### Short jobs on the pc, long jobs on the homelab (Erik, 2026-10-21)

The pc has a fast CPU: compile, build, typecheck and test on it as usual.
What Erik minds is something hogging it for minutes. **Rule of thumb: if a job
will take ~10+ minutes, or turns out to, run it on the homelab.**

| Long job | How |
|---|---|
| Big Gradle/APK release builds, long test suites, embedding/ML batches, data processing | `heavy -- <cmd>` (synced copy on the homelab worker; `heavy pull <path>` brings results back) |
| An emulator you need for more than a few minutes | `heavy emulator start` (adb forwarded to the pc; gRPC/audio on 8554) |
| Long Nix builds | `nix-remote build ...`, `rebuild --remote` |

`heavy` in short (`heavy --help` for all of it):

```
heavy [--big|--small] [--shell .#android] [-e VAR] -- CMD   run in a synced copy on the worker
heavy pull PATH...                       copy results back (nothing else comes back)
heavy bg NAME -- CMD | heavy logs NAME -f | heavy stop NAME   background jobs and servers
heavy emulator start|stop|status         the one shared emulator; heavy adb ARGS from the pc
heavy status | heavy queue               what runs and what waits
```

One big job (up to 10 GB) and one small job (up to 3 GB) run at once on the
worker; the rest queue, and a job that runs out of memory is killed alone.
A foreground `heavy` job dies with its client: for unattended chains use
`systemd-run --user --collect --unit=NAME heavy -- ...` or `heavy bg --big`.

### The safety net on the pc (`modules/nixos/agent-priority`)

- Agent sessions run in `app-t3code.slice`: idle CPU priority, at most 4 of
  the 16 threads, 9/11 GB RAM, 8 GB swap (zram first), 150/60 MB/s disk. Short builds fit
  fine; never escape the slice with `--slice=`, Docker, sudo or system units.
- `nix` and `rebuild` evaluate here. Whole-system evaluations (3-4 GB, ~2
  minutes) wait for each other under one lock; uncached builds go to the
  homelab builder by themselves. `rebuild` refuses a checkout behind
  origin/main (it would revert others' deploys).
- lag-guard kills agent jobs that keep the agents at their CPU budget for 5+
  minutes, emulators running over 15 minutes, and the biggest job when
  Erik's desktop stalls. The killed process gets the reason on its stderr:
  re-run that job with `heavy`, do not retry it on the pc.

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
3. **Cap parallelism.** Keep the total new load to a few GB on the pc:
   `xargs -P 4`, a worker pool, or batches, never one `&` per item over a
   long list. Start small, watch `free -g`, then scale up if there is room.
4. **Move long work off the pc**: `heavy -- <cmd>` for jobs that take ~10+
   minutes, `nix-remote` for long Nix builds; long-running services belong
   in the homelab. Local LLMs must fit fully in
   GPU memory (see `~/.dotfiles/AGENTS.md`).
5. **Clean up.** Do not leave background jobs, dev servers or loaded models
   running when you are done.

If the pc is already slow (`uptime` load far above 16, or high memory
pressure), do not add to it. Wait, or stop your own jobs first.
