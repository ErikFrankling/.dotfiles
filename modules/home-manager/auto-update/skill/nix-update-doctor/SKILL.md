---
name: nix-update-doctor
description: Run and repair the nightly NixOS update for Erik's machines. Load for the scheduled nightly update session, and whenever a `nix flake update`, rebuild or cache miss in ~/.dotfiles needs diagnosing (a broken package on unstable, a hash mismatch, a removed option, something compiling that should be cached).
---

# Nightly update: run it, repair it

Erik's `pc` and `framework` run NixOS from `github.com/ErikFrankling/.dotfiles`
on nixos-unstable plus several bleeding-edge inputs. Every night the flake
inputs are updated and both system closures are built on the homelab build
server, which is also the binary cache. At 06:00 each machine pulls `main` and
rebuilds with building forbidden.

**The contract: `main` only ever points at a commit whose two closures are
fully built on the homelab.** If you push something that is not built, both
machines fail their update. If you cannot get a build, push nothing.

You are unattended. Do not ask questions. Decide, record why, move on.

## The run

You start in a dedicated clone, clean and at `origin/main`. Never touch
`~/.dotfiles`; that is Erik's working tree.

1. `nix flake update`, then commit `flake.lock` alone ("Update flake inputs").
   If nothing changed, skip the commit and still do step 2: yesterday's push may
   have been someone else's and not built yet.
2. `nix-nightly plan` — lists what the homelab would have to build for each
   host. Read it (see "What may compile").
3. `nix-nightly build` — builds both hosts on the homelab and keeps the results
   alive there. It is slow (an old 4-core machine): run it in the background and
   wait for it rather than polling. It refuses a dirty tree, so commit first.
4. If it fails, repair (below), commit each fix on its own, and build again.
5. When it succeeds: `git pull --rebase origin main`. If that brought anything
   in, build again. Then `git push origin HEAD:main`.
6. End with a short summary: what was updated, what you had to change and why,
   what is held back.

Stop after 5 failed repair rounds or about 3 hours, whichever comes first. Then
push nothing, run `nix-nightly notify "<one sentence Erik can act on>"`, and
write the full story in your final message: what broke, what you tried, what
you would do next.

A partial update is a success, not a failure. Holding one input back and
shipping the rest is the normal outcome of a bad night.

## What may compile

The homelab may compile Erik's own projects (the t3code fork, erikshell, time,
nvim, AGS) and the coding harnesses when no cache has the release yet. Small
things (wrappers, units, config files, fish completions, fhsenv shells,
repacked binaries) do not count.

Anything large in the plan is a bug to fix before building, not something to
wait out: a browser, Electron, a compiler or toolchain (llvm, rustc, gcc, ghc),
the kernel, Qt, webkitgtk, LibreOffice. Find out why it misses the cache:

- **An input that `follows` our nixpkgs** but whose own cache was built against
  a different one. Remove the `follows` line (comment it, with the reason).
- **An override or overlay on a cached package.** Any `overrideAttrs` changes
  the hash of the package and everything that depends on it.
- **`pkgsMaster.<x>` before Hydra built it.** Use the `pkgs` one, or wait.
- **nixos-unstable itself is ahead of the cache.** Rare; the channel only
  advances after Hydra finishes. If it happens, pin nixpkgs back to the
  previous lock entry.
- **Unfree packages** are never cached but are binary repacks; fine.

## Repairs, cheapest first

Find the first real error, not the last line. `nix log <drv>` works against the
builder: `nix log --store ssh-ng://nix-builder <drv>`.

Before blaming upstream, check that upstream agrees: search the nixpkgs issues
and PRs for the package and the error, look at the package's Hydra job, and for
a fix PR check whether it has reached the channel (nixpk.gs/pr-tracker). For a
flake input, read its recent commits and issues. Put the link in the comment
you leave. LLMs guess wrong about Nix; search before you edit.

1. **Hold one input back.** The breakage arrived with one input. Restore just
   its entry and keep the rest:
   `git checkout HEAD~1 -- flake.lock && nix flake update <every input but that one>`,
   or simply `nix flake lock --override-input <name> <previous locked url>`.
   No file other than `flake.lock` changes. Say which input and why in the
   commit message.
2. **Take one package from another nixpkgs.** All three are already imported:
   `pkgs` (nixos-unstable), `otherPkgs.pkgsStable`, `otherPkgs.pkgsMaster`.
   Broken on unstable and the fix is merged but not in the channel yet: use
   `otherPkgs.pkgsMaster.<pkg>`. Broken with no fix in sight: use
   `otherPkgs.pkgsStable.<pkg>`. Leave the old line commented above it with the
   date and the issue link, so it is easy to switch back.
3. **Fix a `follows`.** An input that breaks when forced onto our nixpkgs
   builds with its own pin: comment out its `inputs.nixpkgs.follows`. The
   opposite also happens (an input built against an old GTK or Qt misbehaves at
   runtime): then add the `follows`. `flake.nix` has examples of both, with the
   reasons written next to them.
4. **Refresh a fixed-output hash.** "hash mismatch in fixed-output derivation"
   after a source bump, for example `pnpmDeps` in `overlays/t3code.nix` when the
   fork's lockfile changed: put the `got:` hash in. If the source did not
   change and the hash did, upstream re-tagged; say so in the commit.
5. **Follow a rename or removal.** "The option `x` has been renamed to `y`",
   "`pkgs.foo` has been removed": the message usually names the replacement;
   otherwise read the nixpkgs release notes or the commit that removed it.
6. **Patch it.** A one-line upstream fix that is merged but unreleased:
   `overrideAttrs` with `fetchpatch` and the PR link. This forces a local
   build, so only do it for something small.
7. **Turn it off.** A non-essential package or module that cannot be fixed
   tonight: comment it out (never delete; see `AGENTS.md`) with the date, the
   error and the link. Do not turn off anything the machine needs to boot, log
   in, reach the network or run the desktop; hold the input back instead.

8. **Build it on the PC and hand it over.** Two kinds of derivation cannot be
   built on the homelab at all:
   - Builds that nest a user namespace inside the Nix sandbox
     (`bwrap: setting up uid map: Permission denied`; `vmware-workstation`
     does this). The homelab node is Ubuntu, which denies unprivileged user
     namespaces.
   - Unfree downloads the vendor has since deleted (a 404 on a `.deb` or
     installer) that the PC still has in its store.

   For exactly that derivation: `nix build --no-link --print-out-paths
   <drv>^*` on the PC (it is already there if nothing changed), then
   `nix copy --no-check-sigs --to ssh-ng://nix-builder <path>`, and build
   again. For a deleted download also fix the cause: the package is pinned
   to a version that no longer exists upstream, so move it to a nixpkgs that
   has a current one.

Never: `allowBroken`/`allowInsecure` additions to make an error go away,
`--impure`, disabling a check you do not understand, deleting a module.

## Undo yesterday's workarounds

Before updating, `grep -rn "nix-update-doctor:" --include=*.nix .` and look at
the incident log below. For each workaround still in place, check whether its
reason is gone (the PR reached the channel, the input fixed itself). If so,
remove it as its own commit and let the build confirm. Mark every workaround
you add with a `# nix-update-doctor: <date> <link>` comment so the next run
finds it.

## Rules that come from this repository

- Read `AGENTS.md` in the repo; it wins over this file.
- Everything is declarative. No imperative installs or service commands.
- Never leave a `result` symlink; use `--no-link`.
- Temp files go in the working directory and are deleted before you finish.
- Do not run `rebuild` here. Applying is the machines' job at 06:00.
- Commit messages: one plain sentence saying what changed, a body only when
  the reason is not obvious.

## Incident log

Append one entry per night that needed a repair, newest first: date, symptom,
cause, what fixed it, link. Commit it with the fix. This is how the next run
learns the patterns; keep entries to a few lines.

- 2026-10-14 — `sesh` failed because its build dependency `go-mockery` 3.8.0
  cannot read Go 1.27 export data ("export data version 5 is greater than
  maximum supported version 4"). Cause: nixos-unstable moved to Go 1.27 before
  the 3.8.1 bump reached the channel. Fix: `otherPkgs.pkgsMaster.sesh` in
  `modules/home-manager/tmux.nix` (repair 2).
  https://github.com/NixOS/nixpkgs/pull/573099
- 2026-10-14 — `nix-nightly plan` printed nothing for either host. Cause: a
  dry run does not copy the derivations to the builder, so it answers "don't
  know how to build these paths" and the filter hides that. Until the script
  is fixed, get the list with `nix copy --derivation --to ssh-ng://nix-builder
  <toplevel drvPath>` and then `nix build --dry-run --store
  ssh-ng://nix-builder '<drvPath>^*'`.
- 2026-10-14 — `vmware-workstation` failed on the homelab with `bwrap: setting
  up uid map: Permission denied`. Cause: Ubuntu 24.04 on the node sets
  `kernel.apparmor_restrict_unprivileged_userns=1`. Fix: copied the PC's
  build to the builder (repair 8).
- 2026-10-14 — `google-chrome` 143 from `pkgsStable` (frozen release-25.05)
  404ed on its `.deb`; only machines that already had it could build. Fix:
  take `google-chrome` from `pkgs`.
- 2026-10-07 — `codex-desktop-linux` died with "Official app.asar layout is
  empty" when following our nixpkgs. Cause: its asar repack step depends on the
  nixpkgs it was written against. Fix: dropped `inputs.nixpkgs.follows` for it.
- (older) — `voxtype` vulkan shader link failed under our nixpkgs (shaderc
  version). Fix: no `follows`; it uses its own pin.
- (older) — `lanzaboote` v0.4.3 set `boot.bootspec.enable`, removed in recent
  nixpkgs. Fix: moved to the v1.1.0 tag.
- (older) — `ags-shell` built against its own stale nixpkgs shipped an old
  GTK 4 and ignored the dark theme. Fix: added `follows` (the opposite case).
- (older) — `openscad-unstable` broken on unstable. Fix: took it from stable
  until it built again.
