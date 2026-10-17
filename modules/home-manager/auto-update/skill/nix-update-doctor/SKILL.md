---
name: nix-update-doctor
description: Run and repair the nightly NixOS update for Erik's machines. Load for the scheduled nightly update session, and whenever a `nix flake update`, rebuild, cache miss or evaluation warning in ~/.dotfiles needs dealing with (a broken package on unstable, a hash mismatch, a removed option, a deprecation, something compiling that should be cached).
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
1b. Rebase Erik's T3 Code fork onto the newest upstream nightly (see "T3 Code
   fork"). Hand this to a subagent and wait for it; it ends in its own commit.
2. `nix-nightly plan` — lists what the homelab would have to build for each
   host. Read it (see "What may compile").
3. Clear the evaluation warnings (see "Evaluation warnings"). Evaluate both
   hosts, fix every warning whose fix is clear, one commit each.
4. `nix-nightly build` — builds both hosts on the homelab and keeps the results
   alive there. It is slow (an old 4-core machine): run it in the background and
   wait for it rather than polling. It refuses a dirty tree, so commit first.
5. If it fails, repair (below), commit each fix on its own, and build again.
6. When it succeeds: `git pull --rebase origin main`. If that brought anything
   in, build again. Then `git push origin HEAD:main`.
7. End with a short summary: what was updated, what you had to change and why,
   what is held back, which warnings you fixed and which you left and why.

Stop after 5 failed repair rounds or about 3 hours, whichever comes first. Then
push nothing, run `nix-nightly notify "<one sentence Erik can act on>"`, and
write the full story in your final message: what broke, what you tried, what
you would do next.

A partial update is a success, not a failure. Holding one input back and
shipping the rest is the normal outcome of a bad night.

## Evaluation warnings

Erik wants warnings gone, not reported. Most are a rename, a deprecation or
a changed default with an obvious answer, and they turn into errors a few
releases later if left alone. Collect them for both hosts:

```bash
for h in pc framework; do
  nix eval --raw .#nixosConfigurations.$h.config.system.build.toplevel.drvPath 2>&1 >/dev/null \
    | grep -A8 "evaluation warning"
done
```

For each one, read the warning in full (it usually names the fix) and look it
up: the home-manager or nixpkgs commit that added it, the option docs, the
release notes. Then:

- **A rename or removed alias** (`stdenv.isLinux` → `stdenv.hostPlatform.isLinux`,
  `xorg.libICE` → `libice`): apply it. In Erik's own code, fix it there. If the
  warning comes from an input's code, not this repo, leave it; it is theirs.
- **A changed default** (`gtk.gtk4.theme`, `wayland.windowManager.hyprland.configType`,
  `home.pointerCursor.enable`): the warning almost always offers "keep the
  old behaviour" and "adopt the new one". Keep what Erik has today unless the
  new behaviour is plainly what his config is trying to do, and say which you
  picked. Setting the option explicitly is what silences it. Never pick the
  option that changes how the desktop looks or behaves without a reason; a
  silent visual change at 06:00 is worse than the warning.
- **A real decision** (a setting with two reasonable answers and nothing in
  the config to choose by, or a migration that rewrites a whole module, like
  converting the Hyprland config to Lua): leave it and list it in the summary
  with the link.

Put each fix in its own commit, after the lock commit and before the build,
so one build covers everything. A warning fix that breaks the build is
reverted, not repaired at length; the update matters more.

## T3 Code fork

Erik runs his own fork: `github.com/ErikFrankling/t3code`, branch `erik/main`,
pinned as the `t3code-src` flake input and built by `overlays/t3code.nix`. It
is a handful of commits (dictation, no-auth mode, the personal agent, a desktop
keyring fix) on top of the newest upstream **nightly tag**
(`v<version>-nightly.<date>.<n>` in `pingdotgg/t3code`). It follows nightlies,
not every commit on `main`, so each daily rebase stays small.

Give the subagent this brief:

1. Work in `~/.local/state/nix-nightly/t3code` (clone
   `git@github.com:ErikFrankling/t3code.git` there if missing, add
   `https://github.com/pingdotgg/t3code.git` as `upstream`). Never touch
   `~/projects/personal/t3code`; that is Erik's working copy.
2. `git fetch upstream --tags`, check out `erik/main` at `origin/erik/main`.
   Find the newest nightly tag
   (`git tag --sort=-creatordate | grep -m1 nightly`). If `erik/main` already
   sits on it, report "already current" and stop.
3. Tag the current state `backup/erik-main-<date>` and push the tag, then
   `git rebase --onto <tag> <old-base-tag> erik/main` (the old base is
   `git describe --tags --abbrev=0 --match '*nightly*'`).
4. Resolve conflicts by keeping upstream's code and re-applying the fork's
   intent. Read `docs/local-dictation.md` and `docs/personal-agent.md` first.
   If upstream now does something a fork commit did, drop that commit.
5. Use `nix shell nixpkgs#nodejs_24 nixpkgs#pnpm_11` for node. Run
   `CI=true pnpm install --frozen-lockfile`, then typecheck (`tsc-rs --noEmit`)
   `packages/contracts`, `packages/client-runtime`, `apps/server` and
   `apps/web`, and run the fork's tests:
   `vp test run apps/server/src/DictationDeliveryQueue.test.ts apps/server/src/auth/EnvironmentAuth.test.ts packages/client-runtime/src/operations/commands.test.ts apps/web/src/composer-logic.test.ts`.
   Unset `T3CODE_UNSAFE_NO_AUTH` for the tests; the live server's value breaks
   the auth tests. If any of this fails and cannot be fixed with confidence,
   push nothing, report what broke, and leave the fork where it was.
6. Force-push `erik/main` (`--force-with-lease`).
7. In the dotfiles clone: `nix flake update t3code-src`, set `version` in
   `overlays/t3code.nix` to the tag's version, set the `pnpmDeps` hash to
   `lib.fakeHash`, build once to read the real hash, put it in, and build
   `.#nixosConfigurations.pc.config.home-manager.users.erikf.home.path` with
   `--no-link`. Commit "Rebase the T3 Code fork onto <tag>".

If the fork cannot be rebased tonight, the rest of the update still ships: the
flake keeps the previous fork commit, which is still built.

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

8. **Build it on the PC and hand it over.** An unfree download the vendor has
   since deleted (a 404 on a `.deb` or installer) cannot be fetched on the
   homelab, but the PC may still have it in its store.

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

- 2026-10-15 — the plan listed `electron-unwrapped-44.7.2` (a source build)
  for t3code. Cause: t3code comes from `pkgsMaster`, and master `ef8ffae`
  bumped electron before Hydra built it (404 on cache.nixos.org). Fix: held
  `nixpkgs_master` at `5e59cd3` (repair 1); unhold once the narinfo exists.
- 2026-10-14 — `sesh` failed because its build dependency `go-mockery` 3.8.0
  cannot read Go 1.27 export data ("export data version 5 is greater than
  maximum supported version 4"). Cause: nixos-unstable moved to Go 1.27 before
  the 3.8.1 bump reached the channel. Fix: `otherPkgs.pkgsMaster.sesh` in
  `modules/home-manager/tmux.nix` (repair 2).
  https://github.com/NixOS/nixpkgs/pull/573099
- 2026-10-14 — `nix-nightly plan` printed nothing for either host. Cause: a
  dry run does not copy the derivations to the builder, so it answers "don't
  know how to build these paths" and the filter hid that. Fixed in the
  script: it now copies the .drv closure first.
- 2026-10-14 — `vmware-workstation` failed on the homelab with `bwrap: setting
  up uid map: Permission denied`. Cause: Ubuntu 24.04 on the node denied
  unprivileged user namespaces. Fixed on the node (homelab repo,
  `ops/sysctl/99-homelab.conf`); if it comes back, that file was not
  installed.
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
