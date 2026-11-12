---
name: housekeeping
description: Clean up what agents leave behind on Erik's machines (merged worktrees, dead scratch checkouts, per-worktree build output, stray `result` links) without ever touching agent traces or unfinished work. Every scheduled session (nightly update, T3 Code fork job, morning systems check, health-watch incidents) runs its "Start of run" sweep first and its "End of run" step last. Load it too whenever a task creates a worktree or clone, or when Erik asks to clean up disk.
---

# Housekeeping: clean up first, clean up last

Erik (2026-11-12): "any automatic workflow that makes a new work tree MUST
delete that work tree after the code has been merged so it does not occupy the
disk, and all daily workflows should begin by scanning if there is anything
the previous day left, any trash, mess, unnecessary shit that needs to be
cleaned up." Before this rule, abandoned worktrees, each with its own
`target/` or `node_modules`, filled both drives (2026-11-11: about 130 old
naiaclaw worktrees, 11 t3code worktrees, 64 wasm-box workflow worktrees,
leftover `t3code-rebase*` worktrees from the fork job).

## Never delete these

- **Agent traces, ever.** Erik (2026-11-12): "Never ever get rid of agent
  traces, they are very valuable." That is every transcript, session log and
  run output of any agent: `~/.claude/projects`, `~/.claude_2`,
  `~/.codex/sessions`, `~/.codex/archived_sessions`, `~/.codex*/*.sqlite`,
  `~/.codex-t3`, `~/.t3/userdata`, `~/.local/share/opencode`, `~/.grok`,
  `~/.omp`, `~/agent-traces`, and agent output inside a project or data
  folder (`codex exec --json` JSONL, `prompt.txt`, `stdout.log`/`stderr.log`,
  `outcome.json`, run logs). Do not delete, truncate, prune or rewrite them.
  When a folder that holds traces must go, copy the traces out first (below).
- **Unfinished work.** A worktree or clone with uncommitted changes, or with
  commits that are on no remote branch and in no merged PR. Report it; do not
  delete it.
- **Work in progress right now.** Anything a live process has open or uses as
  its working directory, or that changed in the last 24 hours.
- **Erik's own checkouts** (`~/.dotfiles`, `~/projects/<repo>` main
  checkouts). Only the extra worktrees hanging off them are in scope.
- **Shared caches** (`~/.cache/sccache`, `~/.cache/*`, Go and Cargo caches
  under `/mnt/data/wbox-src/go-shared`, the Nix store). Erik wants build caches
  kept (2026-11-11). Only build output that belongs to one finished worktree
  goes, together with that worktree.

## Start of run: sweep what earlier runs left

Do this before your actual task, every scheduled run. Budget about 15 minutes;
the sweep never blocks the real job.

1. List every extra worktree of every repository agents use:

   ```bash
   for g in ~/projects/*/.git ~/projects/*/*/.git ~/.local/state/*/*/.git; do
     [ -d "$g" ] || continue
     git -C "${g%/.git}" worktree prune
     git -C "${g%/.git}" worktree list --porcelain | awk '/^worktree /{print $2}' | tail -n +2
   done
   ls -d ~/.t3/worktrees/*/* ~/projects/*/.claude/worktrees/* 2>/dev/null
   ```

2. For each worktree decide **merged**, **live** or **unfinished**:
   - live: a process uses it
     (`for p in /proc/[0-9]*; do readlink $p/cwd; done | grep -F "$wt"`) or a
     file in it changed in the last 24 hours
     (`find "$wt" -maxdepth 2 -newermt '-24 hours' -print -quit`, outside
     `node_modules`/`target`). Leave it.
   - unfinished: `git -C "$wt" status --porcelain` is not empty, or its HEAD
     is on no remote branch (`git -C "$wt" branch -r --contains HEAD` empty)
     and not merged. Leave it and list it in your report with path, branch,
     last commit date and why.
   - merged: clean, and its work reached the default branch:
     `git -C "$wt" merge-base --is-ancestor HEAD origin/<default>`, or for
     squash/rebase merges `gh pr list -R <owner/repo> --head <branch> --state merged`
     is not empty, or the branch tip is on the remote and the remote branch
     itself is merged. A worktree whose branch was deleted on the remote after
     a merged PR counts as merged.
3. Remove each merged worktree:

   ```bash
   # 1. keep any agent output that only lives in the worktree
   find "$wt" \( -name node_modules -o -name target -o -name .git \) -prune -o -type f \
     \( -name '*.jsonl' -o -name 'prompt*.txt' -o -name 'stdout.log' -o -name 'stderr.log' -o -name 'outcome.json' \) -print
   #    if that lists anything untracked: copy it to ~/agent-traces/<project>/<worktree-name>/ (rsync -a, keep paths), then verify the copy
   # 2. per-worktree build output that lives outside it (wasm-box lanes symlink target/ to /mnt/data/wbox-target/<lane>)
   readlink "$wt/target"   # if it points into /mnt/data/wbox-target/<lane>, delete that lane dir too
   # 3. remove it
   chmod -R u+w "$wt" 2>/dev/null
   git -C <main checkout> worktree remove --force "$wt"   # --force only after the checks above
   git -C <main checkout> branch -D <branch>              # only when merged
   ```

   For a T3 worktree (`~/.t3/worktrees/<project>/t3-...`), check first that its
   thread is not running (`t3_thread_list`/`t3_thread_read`); a finished
   thread's merged worktree goes.
4. Dated scratch from earlier scheduled runs in the jobs' own state folders
   (`~/.local/state/nix-nightly`, `~/.local/state/t3code-fork`,
   `~/.local/state/systems-check`): old clones and worktrees go by the rules
   above. Their logs, evidence and screenshots are traces: move them to
   `~/agent-traces/<job>/<date>/` instead of deleting. Build output inside
   them (`node_modules`, `target`, `.direnv`, `result` links) goes.
5. `result` symlinks that `nix build` left in any repository: delete them.
6. Write one line per thing removed and per thing left (with the reason) in
   your report under `Housekeeping:`. Never notify Erik about routine cleanup.

If a removal fails or something looks like Erik's own work, leave it and say
so in the report. Do not reach for `rm -rf` on anything you have not checked
with the steps above.

## End of run: remove what you made

Before your final report, remove every worktree, clone and scratch folder this
run created whose work is merged or pushed and no longer needed: the same
step 3 as above. A worktree a follow-up session will continue (an unfinished
handover) stays, and the handover message names its path so the next run can
remove it. "Done" includes this step; a finished job that leaves its worktree
behind is not finished.

## Where kept traces go

`~/agent-traces/<project>/` is the home for traces rescued from folders that
had to go (2026-11-12: `~/agent-traces/bostadsradarn`). Keep the original
relative paths and add a short README saying where they came from. An
off-site backup of all agent traces is being set up (Cloudflare R2, waiting on
Erik to enable R2 on his account); `~/agent-traces` is in its scope.
