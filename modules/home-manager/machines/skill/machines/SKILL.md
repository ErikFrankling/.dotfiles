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
| **k8s** | VM 200 on proxmox: the k3s node for the homelab (Kubernetes node name `naiaclaw`), 8 threads, 52 GB RAM, no swap. `192.168.50.100`. | `ssh k8s`, then `sudo kubectl ...` |
| **nix-builder** | A pod on k8s: Nix build server and binary cache (`https://nix-cache.erikfrankling.duckdns.org`). | `ssh nix-builder`; builds with `nix build --store ssh-ng://root@192.168.50.100:2222` |

- Erik's phone and the laptop away from home reach the LAN over Tailscale.
- The homelab is configured in the homelab repo (`~/projects/personal/homelab`) and applied by Flux. The NixOS machines are configured in `~/.dotfiles`.
- k8s is often CPU-saturated. No pod requests CPU (a Kyverno policy
  zeroes requests, so CPU never blocks scheduling). The homelab
  `cpu-priority` DaemonSet gives the nix-builder `cpu.weight` 10000 and runs
  Onyx indexing and `heavy` jobs at `cpu.idle`, so the nightly
  build goes first.
- Do not start VM 100 on proxmox (its address collides with the k3s VIP). Never reboot or power off any machine.

## Do not overload the pc

The pc is the machine Erik is sitting at. When it runs out of memory it does
not crash, it swaps. The desktop freezes and T3 Code stops answering. That
includes on his phone, and it includes the session you are running in.

### Short jobs on the pc, long jobs on the homelab (Erik, 2026-10-21)

The pc has a fast CPU: compile, build, typecheck and test on it as usual.
Large workloads may run here too (Erik, 2026-11-12: the old 4-core cap was
"really in the way when I need agents to do large scale workloads"); nothing
kills a job for running long. **Rule of thumb: a job of ~10+ minutes that the
homelab can run just as well goes there; what must not happen is the pc
running out of memory.**

| Long job | How |
|---|---|
| Big Gradle/APK release builds, long test suites, embedding/ML batches, data processing | `heavy -- <cmd>` (synced copy on the homelab worker; `heavy pull <path>` brings results back) |
| An emulator you need for more than a few minutes | `heavy emulator start` (adb forwarded to the pc; gRPC/audio on 8554) |
| Long Nix builds | `nix-remote build ...`, `rebuild --remote` |

`heavy` in short (`heavy --help` for all of it):

```
heavy [--big|--small] [--priority] [--shell|--small] [--shell .#android] [-e VAR] -- CMD   run in a synced copy on the worker
heavy pull PATH...                       copy results back (nothing else comes back)
heavy bg NAME -- CMD | heavy logs NAME -f | heavy stop NAME   background jobs and servers
heavy emulator start|stop|status         the one shared emulator; heavy adb ARGS from the pc
heavy status | heavy queue               what runs and what waits
```

One big job (up to 10 GB) and one small job (up to 3 GB) run at once on the
worker; the rest queue, and a job that runs out of memory is killed alone.
### Long jobs survive your session and T3 restarts (`agent-job`)

When T3 Code's server restarts, it stops every agent's scope and slice. So does
a session that ends, and a tool call that times out kills what it started. On
2026-10-23 that silently killed the nightly's homelab build. So from a
session, these run as their own user unit, `agent-job-NAME.service` in
`app-t3code-jobs.slice` (same caps as the agents, but outside what T3 stops):

| Command | Job name |
|---|---|
| `nix-nightly build` | `nix-nightly-build` (nightly clone) or `nix-nightly-build-adhoc-<hash>` |
| `rebuild` (`nixos-remote-switch`) | `rebuild-<host>-<hash of checkout>` |
| `heavy -- CMD` | `heavy-<hash of directory + arguments>` |
| any `systemd-run --user` service (not `--scope`) | the `--unit` you give |

- **Wait by running the same command again**: if its job is still running,
  you attach to it instead of starting a second one. You get its output from
  the start of the log, and its exit code at the end. After a restart or a
  timed-out tool call, just re-run it.
- Interrupting or killing the command only detaches. The job keeps running.
- `agent-job status` lists jobs. Also `agent-job status|attach|logs|stop NAME`.
  Logs are in `~/.local/state/agent-job/NAME.log`.
- Your own long command: `agent-job run NAME -- CMD...`, then
  `agent-job attach NAME` from any later turn or session. Run it in the
  foreground; don't add `&` or nohup.
- Never `pgrep` for a build to see whether it still runs (the pattern matches
  your own shell). Use `agent-job status NAME`.
- `AGENT_JOB=off CMD` runs it in your session the old way.

### The safety net on the pc (`modules/nixos/agent-priority`)

- Agent sessions run in `app-t3code.slice`: low CPU priority behind Erik's
  apps on all 16 threads, 20/22 GB RAM (throttled / killed), 12 GB swap
  (zram first), 150/60 MB/s disk (Erik, 2026-11-13: "just use my full pc").
  The same caps whether Erik is at the pc or not. Never escape the slice
  with `--slice=`, Docker, sudo, system units or your own `systemctl
  set-property`.
- 20 GB is a ceiling, not what is there. Erik's apps are protected with
  `memory.low` (9.5 GB) and usually take about 14 GB of RAM with what they
  hold compressed in zram, so on a normal day the agents together get about
  14 GB before the machine itself is full. Then the kernel swaps the agents
  first, and lag-guard stops the biggest job when Erik's apps stall.
- To pace builds, read these, not `/proc/pressure/io` or
  `/proc/pressure/memory` (system-wide, and the io figure counts agents
  waiting on their own disk cap: 83 % with idle disks on 2026-11-13). With
  `A=/sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service/app.slice/app-t3code.slice`:
  `$A/memory.pressure` (the agents' own stall; hold back above ~10 % `full
  avg10`), `$A/memory.current` against `$A/memory.high`, `MemAvailable` in
  `/proc/meminfo` (start nothing new under ~3 GB), and for disk `$A/io.max`
  (a line with `rbps=20000000` or lower means lag-guard has the agents
  capped; `ls /run/lag-guard/base-*` lists the capped disks).
- `nix` and `rebuild` evaluate here. Whole-system evaluations (3-4 GB, ~2
  minutes) wait for each other under one lock; uncached builds go to the
  homelab builder by themselves. `rebuild` refuses a checkout behind
  origin/main (it would revert others' deploys).
- lag-guard acts when Erik's desktop stalls. On memory, when the kernel
  starts reclaiming his protected memory, or when the agents thrash (their
  slice stalled on memory while his apps stall on disk), it kills the
  biggest agent job by RSS. On disk IO, and only when the stalled device is
  over 50 % busy, it first cuts the agents' bandwidth
  on the stalled disk in three steps (down to 20 MB/s read, 5 MB/s write;
  given back when the desktop is calm), and only if the stall goes on kills
  the job doing the most IO on that disk. So big scratch files (disk images,
  dumps, task output) go to `/mnt/data`, not `/tmp` or `~`: the system disk is
  the one Erik's apps wait on. A shared job many sessions wait on sets
  `AGENT_JOB_PRIO=1` in its environment: it is passed over as a victim while
  any other candidate exists (never for a session's own work), and gets a
  30-minute head start in the homelab queue with `heavy --priority` (it
  never passes a job that has waited longer than that). Nothing is killed for running
  long or for using CPU. The
  killed process gets the reason on its stderr: re-run that job with `heavy`
  or with fewer parallel jobs, do not retry it unchanged on the pc.
- Memory is what runs out, not CPU: 16 threads of rustc or a dozen parallel
  builds do not fit in 14 GB. Size `-j` and the number of parallel jobs to
  the memory, and send what does not fit to `heavy`.

### There is no max mode (removed 2026-11-12)

`agent-max` (4 cores normally, 14 while Erik was away) is gone. Erik: "now
it's really in the way when I need agents to do large scale workloads". Do
not tell him to turn anything on, and do not ask whether he is away: the
caps above always apply.

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

When Erik reports lag, a freeze or a spike, do not look at `top` now: the
moment has passed. Load the `system-history` skill and rank what ran at
that time (per program, unit and T3 thread, recorded every 5-30 s).

## Windows

Anything an agent session starts opens on `AGENT-1`, workspace `agent`, enforced
by the Hyprland plugin `packages/agent-windows`: run the program, no rule needed.
`window-origin` says which process, cgroup and thread opened any window. Details:
AGENTS.md, computer-use skill.
