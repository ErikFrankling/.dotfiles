---
name: systems-check
description: Morning systems check of Erik's machines and homelab. Load for the scheduled morning check session, and whenever Erik asks whether "everything is working", for a health check of the pc, the framework laptop or the homelab, or why the daily update did not land somewhere.
---

# Morning systems check: verify, repair, report

Erik does not want to be a sysadmin. Every night at 03:00 a session updates
the dotfiles and builds both machines on the homelab (`nix-update-doctor`
skill); at 06:00 each machine applies `main`. You run at 07:00 and own the
result: make sure the **pc**, the **framework** laptop and the **homelab** are
all in working order, repair whatever is not, and send Erik **exactly one**
notification saying how things stand.

You are unattended. Do not ask questions. Erik has authorized this session to
repair all three systems, within the limits below.

## Where things are

- You start in `~/.local/state/systems-check/dotfiles`, a clean clone at
  `origin/main`. The homelab repo is cloned next to it in
  `~/.local/state/systems-check/homelab`. Both are yours to commit in.
- Never touch Erik's own checkouts (`~/.dotfiles`,
  `~/projects/personal/homelab`); they may hold work in progress.
- `ssh framework` reaches the laptop through the Proxmox host's Tailscale
  node, at home or away. It fails when the laptop is asleep or off.
- `ssh naiaclaw` is the k3s VM (`sudo kubectl ...`), `ssh proxmox` the
  hypervisor (root), `ssh nix-builder` the build server / binary cache.
- Read `AGENTS.md` in both repos before changing either. Nightly state:
  `~/.local/state/nix-nightly/` and the nightly thread in T3 Code.

## The run

1. `systems-check status`. It prints facts for the nightly build, each host
   and the homelab; anything in capitals (`NO`, `UNREACHABLE`, `FAILED`,
   `NEW KERNEL`, `STILL RUNNING`) deserves a look. It takes a few minutes
   (it evaluates both systems).
2. For each problem, find the cause, not the symptom, and repair it (below).
   Repairs that change a system closure go through the build: commit in your
   clone, `nix-nightly build`, then push. The contract from
   `nix-update-doctor` holds: `main` only moves to commits that are built.
3. Run `systems-check status` again to confirm the repair held.
4. Send the report (below), then end with a short summary: what you found,
   what you fixed and how, what is left for Erik.

Stop repairing after about 2 hours. Report what is still broken; a clear
report beats a half-finished fix.

## What "working" means

**Each machine** runs `main`'s system (`runs main: yes`), has no failed units
that matter, and has disk to spare. A different running system has a few
known causes:

- `main is built: NO`: someone pushed after the nightly build (the 06:00
  dotfiles-sync often does this). The machines correctly refused to apply.
  Run `nix-nightly build` from your clone (it builds `HEAD`, which is
  `origin/main`), then start the update on each machine:
  `systemctl --user start auto-update` (pc locally, framework via ssh). It
  pulls and switches without building.
- The nightly did not push at all: read its thread and
  `~/.local/state/nix-nightly/`; the `nix-update-doctor` skill has the
  repairs. A night with no update is fine to report, not to panic over.
- The 06:00 run failed or never ran: read `journalctl --user -u auto-update`
  and `journalctl -u 'auto-update-switch-*'` on that machine, fix the cause,
  rerun it as above.
- The framework is unreachable: it is asleep, off or on battery. That is
  normal, not a fault. Its own update runs on the next wake on mains power at
  home. Report when it was last seen on the tailnet.
- `NEW KERNEL`: the update is applied but only takes effect after a restart.
  Never reboot anything yourself; tell Erik.

**The homelab** is: Flux not suspended and applied at homelab `main`; every
Deployment ready; no pods failing in `homelab`, `flux-system`, `kube-system`,
`cert-manager` or `traefik`; the nix cache answering; the wildcard certificate
more than 20 days from expiry; DuckDNS resolving to `192.168.50.100`; VM 200
running, VM 100 stopped; disk and memory not near full on the VM and the host.

- Homelab changes go in git and Flux applies them. Do not `kubectl apply` or
  edit live objects instead, and never suspend Flux; that is how the
  2026-10-15 incident happened. If Flux is suspended, `kubectl diff` live
  against git first, fold any live-only change into git, then resume it.
- Pods in `Error`/`ContainerStatusUnknown` that belong to a ReplicaSet or Job
  which has since succeeded are leftovers; deleting `status.phase=Failed`
  pods is safe. A pod failing *now* is a real fault: read its logs.
- The `naiaclaw-system`, `p9` and `nc-*` namespaces are Erik's other
  projects, not homelab infrastructure. Report their failures in one line;
  do not repair them.

## Limits

- Never reboot or power off a machine, VM or node. Never start VM 100 (its
  address collides with the k3s VIP).
- Never delete PVs, PVCs, volumes, databases or anything with user data.
- Never commit a secret in plaintext; both repos use SOPS. The homelab repo
  is public.
- Never force-push. Never rewrite `main`.
- A service restart or a `kubectl rollout restart` is fine when it is the
  repair; say so in the report.
- Imperative changes to a NixOS machine are not repairs. Fix the dotfiles.

## The report

Exactly one call, at the end:

```bash
systems-check report ok "<body>"         # everything works
systems-check report attention "<body>"  # Erik has to do something
```

`ok` also covers things you repaired and things that sort themselves out
(the laptop asleep). Use `attention` only when Erik must act (restart for a
kernel, something you could not fix) and put that action in the first line.

The body is one short line per system, then at most one line on repairs:

```
PC: updated to 3f58edd (inputs of Oct 15)
Framework: updated to 3f58edd
Homelab: healthy
Fixed: Flux was suspended since Aug 21; resumed it at homelab main.
```

Other examples of lines: `PC: restart when convenient, new kernel 6.18.55`,
`Framework: asleep since 22:10, updates on next wake`, `Homelab: naiaclaw
event-sweep failing (not homelab, left alone)`. No paths, no hashes beyond the
short rev, no log excerpts; the thread has the details.

## Incident log

Newest first; one entry per morning that needed a real repair.

- 2026-10-15 — Homelab not applying anything since 2026-08-21: the Flux
  Kustomization had `suspend: true`, and later changes were applied by hand
  with `kubectl`. 315 dead pods had piled up. Fix: diffed live against git,
  committed the one live-only change (planet9-test route middleware), resumed
  Flux, deleted `Failed` pods. Also: `ssh framework` pointed at a stale DHCP
  address; it now goes through the Proxmox Tailscale node.
