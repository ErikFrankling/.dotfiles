---
name: dotfiles-sync
description: Get Erik's ~/.dotfiles checkout committed, merged with origin/main and pushed. Load when the daily auto-update asks for it, or when Erik asks to sync, commit or push local dotfiles work, or to resolve a dotfiles merge conflict.
---

# Syncing local dotfiles work

Erik changes his NixOS config in small steps on two machines (`pc`, `framework`)
and often applies them with `rebuild` without committing. The daily update
starts you when `~/.dotfiles` has uncommitted changes or commits that are not on
`origin/main`. Your job ends when all three of these hold:

- `git status --porcelain` is empty
- the branch is `main`
- `HEAD` equals `origin/main` after a fresh `git fetch`

The caller checks exactly that. Do not run `rebuild` or any other Nix build;
applying the result is someone else's step.

## The repository is public

`github.com/ErikFrankling/.dotfiles` is public, and what you push is published.
Before committing, read the diff of every file you are about to add.

- Never commit a plaintext secret: tokens, passwords, private keys, API keys,
  `.env` contents, anything that looks like a credential. SOPS-encrypted files
  (`hosts/*/secrets/*`, with `ENC[` values and a `sops:` block) are fine.
- Never commit agent scratch (`.claude/worktrees/`, temp output, `result`
  symlinks, build logs). Delete obvious scratch; leave anything you are unsure
  about untracked and say so.
- If a file may contain a secret, do not commit it and do not push. Leave it
  where it is, commit the rest if that is clean, and end by saying which file
  stopped you. An unfinished sync is fine; a leaked secret is not.

## Steps

1. Look first: `git status`, `git diff`, `git log origin/main..HEAD`,
   `git log HEAD..origin/main`.
2. Commit the local work. Group it into focused commits by what each change is
   for, not one "local changes" commit. Write messages the way the existing
   history does (`git log --oneline -20`): a plain sentence saying what the
   change does. Follow `AGENTS.md` in the repo.
3. Bring in main: `git pull --rebase origin main` when the local commits are
   simple, a merge when a rebase would be messy.
4. Resolve conflicts by understanding both sides. Usually both changes are
   wanted and the resolution keeps both.
   - `flake.lock`: take main's version (`git checkout --theirs`/`--ours` as
     appropriate for the operation), then run `nix flake lock` so inputs the
     local side added get an entry. Never `nix flake update` here.
   - A module one side commented out and the other edited: keep it commented
     out with the edit applied inside the comment only if that is clearly what
     both meant; otherwise prefer the side that is newer in time.
5. Check that the config still evaluates for this host:
   `nix eval --raw .#nixosConfigurations.<host>.config.system.build.toplevel.drvPath`.
   Fix what the merge broke. If the local work itself does not evaluate and the
   fix is not obvious, still commit and push it only if main keeps evaluating
   for both hosts; otherwise stop and report.
6. `git push origin main`.

## Never lose work

No `git reset --hard`, no `git checkout -- <file>`, no `git clean`, no dropping
a stash, no force-push. If you cannot finish safely, leave the tree as it is
and explain in your final message what is in the way. Erik gets a notification
and will look.
