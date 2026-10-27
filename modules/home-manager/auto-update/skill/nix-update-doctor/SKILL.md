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

## The night

| Time  | What                       | Who                                    |
| ----- | -------------------------- | -------------------------------------- |
| 01:00 | prebuild: update + build   | `nix-nightly prebuild`, no agent       |
| 03:00 | the run below              | this session                           |
| 04:00 | T3 Code fork job           | its own session ("T3 Code fork job")   |
| 06:00 | machines apply `main`      | `auto-update`                          |

The 01:00 prebuild updated every input except `t3code-src` in a clone of its
own and built both hosts on the homelab without an agent, up to 110 minutes.
So tonight's slow compiles (a nixpkgs bump rebuilds Hyprland through the
Aquamarine overlay, 68 minutes) are normally done before you start, and when
the update broke something, its result already names the failing derivation.
A normal night then takes 10 to 20 minutes.

There is no time limit. A big update may need to take long; a run that takes
long for no reason is a bug. Telling the two apart is your job, at the
checkpoint below. `nix-nightly elapsed` shows how long the run has taken and
what the build is doing.

## The 50-minute checkpoint

Erik (2026-10-25): "If it takes more than 50 minutes, part of the instructions
to the update: investigate why it's taking long. Sometimes it is a big update
that needs to take long. Sometimes it doesn't need to take long."

When the run has taken 50 minutes (`nix-nightly elapsed` says "PAST the
50-minute checkpoint", or a message starting "Checkpoint:" arrives in this
thread; it is sent at 50 minutes), stop what you are doing and investigate
before anything else. Do not cancel a running build just because it is
long, and do not hurry to finish.

1. **Find what takes the time.** `nix-nightly elapsed` lists what the build is
   building now and since when. Name the derivation(s) and how long they have
   been building; for a step that is not a build (an evaluation, a test run, a
   wait), name that step. Look at your own last steps too: how many builds you
   ran and why.
2. **Decide whether it is justified.** Justified: a large build that tonight's
   update really ships. A kernel, a toolchain, Hyprland for a nixpkgs bump
   that stays in the lock, one of Erik's own projects. The prebuild timed out
   on it, or main moved after 01:00. Waste: something that will be thrown away
   (a build for an input you are about to hold back, a build outside
   `nix-nightly build`, a closure for a lock you already changed), a hung
   process (no new log lines for 15 minutes, a stuck `ssh` or evaluation), a
   retry loop (the same commit built again, the same failure twice), or a
   large compile that is a cache miss with a fix in "What may compile".
3. **Act on it.** Justified: let it run and carry on with the run. Waste: fix
   the cause (hold the input back first, drop the override, stop the hung
   job with `agent-job stop <name>`, stop retrying), or stop that part of the
   run and ship the rest.
4. **Tell Erik the cause**, once:
   `nix-nightly notify "<cause>, <how long>, justified|not justified: <what you did>"`,
   for example
   `nix-nightly notify "Hyprland recompiled for nixpkgs 3ec6363 (Aquamarine overlay), 68 min so far, justified: nixpkgs ships tonight, letting it finish"`.
   Never only the symptom ("the update is slow", "took 2 h").

Then go on with the run; the summary (step 7) repeats the finding.

## The run

You start in a dedicated clone, clean and at `origin/main`. Never touch
`~/.dotfiles`; that is Erik's working tree.

1. `nix-nightly update`. It takes the prebuild's `flake.lock` when the
   prebuild started from the `flake.lock` main still has, else runs the
   update itself, commits it ("Update flake inputs") and prints the
   prebuild's result. `t3code-src` is never updated here; the fork job owns it.
   If nothing changed, still do step 3: yesterday's push may have been someone
   else's and not built yet.
2. Read the prebuild result.
   - **OK:** everything is cached; go to step 3, skip `plan`.
   - **FAILED:** repair first (below), using the errors it printed and
     `~/.local/state/nix-nightly/prebuild/build.log`. Do not build just to see
     the error again.
   - **TIMED OUT, or no prebuild** (it printed "updating now"): run
     `nix-nightly plan` and read it (see "What may compile"). Decide before
     building whether each large compile is justified (see the checkpoint).
     One for an input you will hold back anyway is not: hold it back first.
3. `nix-nightly build` — builds both hosts on the homelab and keeps the results
   alive there; about 3 to 6 minutes when the prebuild built everything. Start
   it as a background command and wait for it inside your turn. Write its
   output **outside the clone** (`nix-nightly build > ../build.out 2>&1`) or
   not at all; it keeps its own logs in `~/.local/state/nix-nightly/`.
4. If it fails, repair (below), commit each fix on its own, and build again.
   Each build must test a different fix; never rerun the same commit hoping it
   passes.
5. When it succeeds: `git pull --rebase origin main`. If that brought anything
   in, build again. Then `git push origin HEAD:main`.
6. Clear the evaluation warnings (see "Evaluation warnings"), one commit each,
   build once more and push.
7. End with a summary that **leads with the cause** of anything that took
   long or failed: "Hyprland recompiled for nixpkgs 3ec6363, 68 min,
   justified", or "nss-cacert fails its blocklist check on 3ec6363, held
   nixpkgs back", never "took 2 h". Then: what was updated, what you had to
   change and why, what is held back, which warnings you fixed and which you
   left and why, and how long the run took (`nix-nightly elapsed`). A run past
   50 minutes includes the checkpoint's finding.

Builds happen only through `nix-nightly build` and `nix-nightly plan` (they
run on the homelab). Never a bare `nix build` of a closure or `home.path` in
the run: on 2026-10-25 one ran for 84 minutes and compiled a Hyprland for a
nixpkgs that was then held back anyway.

Stop after 5 failed repair rounds. Then push nothing, run
`nix-nightly notify "<the cause, in one sentence Erik can act on>"`, and write
the full story in your final message: what broke, what you tried, what you
would do next.

A partial update is a success, not a failure. Holding one input back and
shipping the rest is the normal outcome of a bad night, and the fastest
repair: prefer it whenever the cause is not obvious.

## Evaluation warnings

Erik wants warnings gone, not reported. Most are a rename, a deprecation or
a changed default with an obvious answer, and they turn into errors a few
releases later if left alone. Collect them for both hosts:

```bash
for h in pc framework; do
  nix-remote eval --raw .#nixosConfigurations.$h.config.system.build.toplevel.drvPath 2>&1 >/dev/null \
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

Put each fix in its own commit, after the update is pushed (step 6), so one
more build covers them all. A warning fix that breaks the build is reverted,
not repaired at length; the update matters more.

## T3 Code fork

Erik runs his own fork: `github.com/ErikFrankling/t3code`, branch `erik/main`,
pinned as the `t3code-src` flake input and built by `overlays/t3code.nix`. It
is a handful of commits (dictation, Android dictation and read aloud, no-auth
mode, the personal agent, a desktop keyring fix) on top of the newest upstream
**nightly tag**
(`v<version>-nightly.<date>.<n>` in `pingdotgg/t3code`). It follows nightlies,
not every commit on `main`, so each daily rebase stays small.

The fork also builds Erik's phone app: every push to `erik/main` runs
`.github/workflows/erik-android.yml` on GitHub Actions, which publishes a signed
JS update or, after a native change, an APK; the app installs either by itself
(the fork's `docs/erik-updates.md`). So the force-push in step 6 is also the
phone update. The run refuses to publish if `erik/main` lost a commit that was
already shipped (same patch or same subject counts as kept), so never drop or
reword fork commits in the rebase; after it, check the run
(`gh run list -R ErikFrankling/t3code --workflow erik-android.yml --limit 1`).
A failed run does not block the rest of the update (the phone keeps the
previous build), but repair it if the cause is clear: usually a conflict
re-applied wrongly in `apps/mobile`, or a new upstream native dependency.
Re-run with `gh workflow run erik-android.yml -R ErikFrankling/t3code --ref erik/main`.

## T3 Code fork job

**No human ever attends this job.** Erik writes none of the fork's code:
every fork commit was written by an agent, and every rebase, conflict
resolution, test run, emulator check and release is this job's, however big.
Being unattended is the normal state of this job, never a reason to stop.
Erik (2026-10-27), after a run stopped with "resolving it unattended isn't
safe" and asked him to rebase by hand: "At no point has there ever been a
human attending to anything. Just do that yourself. It should never have to
ask about that."

- Never stop with "not safe unattended", "needs an interactive session",
  "someone should test …" or "a human should review". Never ask Erik
  anything. A large upstream change (hundreds of files, a rewrite of a
  feature the fork extends, dozens of conflicting commits) is ordinary work:
  port the fork's behaviour onto upstream's new code and verify it yourself,
  including the phone flows on the emulator (step 6).
- Notify Erik only with results, once, at the end:
  `nix-nightly notify "T3 fork rebased onto <tag>: <n> commits kept, <m> dropped; released <APK or OTA id>"`.
  Never a request for help, a question or a decision for him.
- Keep the old build live meanwhile. `erik/main`, `t3code-src` and the phone
  stay where they are until the rebased tree passes steps 5 and 6; the flake
  keeps the previous fork commit, which is built. Work in a worktree, never on
  the clone's `erik/main` checkout.
- If the job cannot finish in this session (the rebase is too big for the
  night, the context runs low, a fix needs more than this session has),
  **continue it in a follow-up session; never stop and report.** Commit your
  progress to the rebase branch first, then start the follow-up with
  `t3_thread_launch` in the dotfiles T3 project (project id
  `d16c5128-fa5d-4f7e-bf79-9b395f60962b`), on Opus
  (`modelSelection: {"instanceId":"claudeAgent","model":"claude-opus-5-5"}`),
  with a message that carries this authority word for word: "Continue the T3
  Code fork rebase onto <tag> from <worktree path>, branch <branch>, stopped
  at <step and commit>. Follow the 'T3 Code fork job' section of the
  nix-update-doctor skill to the end. No human attends this job and none
  ever will: never ask a human anything and never stop because the work is
  unattended or large. You may rewrite and force-push erik/main (the backup
  tag stays), change and push the dotfiles, build on the homelab, restart T3
  Code (an expected restart) and publish the phone build or OTA. Notify Erik
  only with the result." Then end this session; the follow-up owns the job.

The rebase is a session of its own at 04:00 (`t3code-fork.timer`), in its own
dotfiles clone (`~/.local/state/t3code-fork/dotfiles`), never part of the
03:00 run. By 04:00 `main` is built, so the only thing that compiles is
t3code itself (about 11 minutes on the homelab); a quiet night takes 20 to 30
minutes, a big upstream change hours. "The 50-minute checkpoint" applies here
too, with the same message at 50 minutes (`nix-nightly elapsed` works in this
clone); a big rebase is a justified reason to take long.

This session runs on Sonnet. Conflict work on a big rebase (conflicts in more
than about five files, or any in the mobile voice, dictation or read-aloud
code) goes to Opus: `delegate_task` it with the whole brief, or hand the job
to the Opus follow-up session above.

Do the steps below yourself, in order. Report in the summary with the cause
first, as in step 7 of the run.

1. Work in `~/.local/state/nix-nightly/t3code` (clone
   `git@github.com:ErikFrankling/t3code.git` there if missing, add
   `https://github.com/pingdotgg/t3code.git` as `upstream`). Never touch
   `~/projects/personal/t3code`; that is Erik's working copy.
2. `git fetch upstream --tags`, check out `erik/main` at `origin/erik/main`.
   Find the newest nightly tag
   (`git tag --sort=-creatordate | grep -m1 nightly`). If `erik/main` already
   sits on it, report "already current" and stop.
3. Tag the current state `backup/erik-main-<date>` and push the tag. Rebase in
   a worktree with rerere on: `git config rerere.enabled true`,
   `git worktree add -b rebase/<date> ../t3code-rebase erik/main`, then
   `git rebase --onto <tag> <old-base-tag> rebase/<date>` (the old base is
   `git describe --tags --abbrev=0 --match '*nightly*' erik/main`).
4. Resolve every conflict; there is no size at which you stop. Keep
   upstream's code and re-apply the fork's intent, read from the fork commit's
   message (`git show REBASE_HEAD`). Where upstream rewrote something the fork
   extends, port the fork's behaviour onto upstream's new design instead of
   forcing the old code back. Read `docs/local-dictation.md` and
   `docs/personal-agent.md` first. If upstream now does something a fork
   commit did, drop that commit (`git rebase --skip`). For `pnpm-lock.yaml`
   take the upstream side at each stop and regenerate it in step 5; for
   `apps/web/src/routeTree.gen.ts` take upstream's and regenerate it.
5. Install, typecheck and test on the homelab (`heavy --big --no-develop --
   nix shell nixpkgs#nodejs_26 nixpkgs#pnpm_12 -c <script>`, output redirected
   to a file, `< /dev/null`; pull results with `heavy pull`). Run
   `CI=true pnpm install --no-frozen-lockfile` (commit the lockfile change),
   regenerate the route tree, typecheck (`node_modules/.bin/tsc --noEmit -p .`)
   `packages/contracts`, `packages/shared`, `packages/client-runtime`,
   `packages/provider-core`, `apps/server`, `apps/web`, `apps/mobile` and
   `apps/desktop`, and run those packages' test suites (their `test` scripts).
   Unset `T3CODE_UNSAFE_NO_AUTH` for the tests; the live server's value breaks
   the auth tests. A failure is yours to fix (a commit "fix: rebase fallout
   onto <tag>"); compare with the same suite on the bare upstream tag to tell
   fork breakage from upstream's own. Never ship a failing tree, and never
   stop because of one: fix it, or hand over to the follow-up session.
6. When the rebase touched mobile code, prove dictation and voice mode on the
   emulator yourself (`heavy emulator start`; the brain's "T3 phone voice mode
   ... emulator proof" and "T3 Android: emulator proof on the shared homelab
   emulator" entries have the recipe). Never open a window on Erik's monitors
   (DP-3, HDMI-A-1).
7. Force-push `erik/main` (`--force-with-lease`); the backup tag stays.
8. In the dotfiles clone: `nix flake update t3code-src`, set `version` in
   `overlays/t3code.nix` to the tag's version if it is a release number, and
   set the `pnpmDeps` hash to `lib.fakeHash`. Read the real hash with a
   bounded homelab build that stops at the first failure, the pnpm fetch:
   `timeout 15m nix-remote build --no-link .#nixosConfigurations.pc.config.home-manager.users.erikf.home.path 2>&1 | grep -m1 'got:'`.
   Put it in, commit "Rebase the T3 Code fork onto <tag>".
9. `nix-nightly build` (output outside the clone), then
   `git pull --rebase origin main` and `git push origin HEAD:main`. If the
   build fails on something other than t3code, that is not this job's to
   repair: push nothing, keep the fork pushed, and report it.
10. Publish the phone update with `t3-android-release` (it decides between a
    JS OTA and an APK from the native fingerprint).

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
- 2026-10-25 — The run took 1 h 49 min. The fork subagent's unbounded local
  `nix build ... home.path` (03:07–04:31) compiled Hyprland 0.56.2 for
  nixpkgs `3ec6363` (68 min on the homelab), and that nixpkgs was then held
  back because `nss-cacert` 3.131.1 fails its blocklist check there, so the
  Hyprland was never used. `nix-nightly build` also refused twice (exit 2,
  10-24 03:19 and 10-25 04:37) because the session wrote `build.log` into
  the clone. Fix: the 01:00 prebuild, the fork job at
  04:00, `build` ignores untracked files, and a 50-minute checkpoint where the
  session finds out why it takes long (no hard limit: Erik, 2026-10-25).
- 2026-10-23 — Same two holds as 10-22: `nixpkgs` update to `02c087f`+ still
  fails in `linux-6.18.57-modules` (vmware-modules, nixpkgs#575192 open; the
  v4l2loopback PR #575861 merged 10-21), and `nixpkgs_master` `a86be0c`+ needs
  uncached `electron-unwrapped-44.9.3`. Held `nixpkgs` at `55bfb4d`, `nixpkgs_master`
  at `39df354`. Unhold when the issue closes and master's electron is cached.
  Evaluation warnings left: xorg.* / stdenv.isLinux renames, all from nixpkgs
  packages, none in this repo.
- 2026-10-22 — (1) `nixpkgs` update to `02c087f` again failed in
  `linux-6.18.57-modules`: v4l2loopback `modules.dep` collision. Held `nixpkgs`
  at `55bfb4d` again (still unfixed; issue #575192 / PR #575861). (2) `nixpkgs_master`
  `96ff2df` needed uncached `electron-unwrapped-44.9.3` for t3code; held at
  `44996b0`. (3) `VMware-Workstation-Full-25H2u1` download from archive.org
  returned 500 on the builder (works from the PC): downloaded with curl on the
  PC, `nix store add --mode flat --name <bundle name>`, `nix copy` to the builder.

- 2026-10-20 — pc failed in `linux-6.18.57-modules` (the module aggregator).
  Cause: nixpkgs `09063bd` makes `aggregateModules` merge per-module
  `.ko.cer` files (#571181), and external modules that skip Kbuild's
  `modules_install` have none: `vmware-modules` (pc) fails with "cat:
  misc/vmmon.ko.cer: No such file". v4l2loopback 0.15.4 also collides on
  `modules.dep` (fix: #575861, works as an `overrideAttrs` with
  `installFlags = [ "DEPMOD=true" "INSTALL_MOD_PATH=..." ]`). No vmware fix
  upstream yet. Fix: held `nixpkgs` at `55bfb4d` (repair 1); unhold when
  vmware-modules and v4l2loopback build with the new aggregator.
  https://github.com/NixOS/nixpkgs/issues/575192
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
