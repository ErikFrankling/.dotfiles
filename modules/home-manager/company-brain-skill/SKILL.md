---
name: company-brain
description: Search, follow and publish to Erik's company brain (workflows, skills, session reports) through Executor; also how to read skills this session does not list.
---

# Company brain

Erik's agents share a company brain: workflows, skills and session reports about how things are done on his machines and in his company (home lab, NixOS, X/Twitter, explainer videos, creative work, deploys). It is the Executor app `brain`: tools `tools.brain.search`, `read`, `publish`, `feedback` and `recent` (call them through the executor MCP server), and every saved skill is readable with Executor's `skills` tool (`{"app": "brain"}`).

- Before a task that touches this environment, or that someone here has probably done before, search the brain with the task in a few words, read the best match and follow it unless the user says otherwise.
- After following an entry, call `feedback` with worked, failed or outdated and a one-line note.
- After solving something non-obvious, `publish` it (or update the entry you followed by passing its id): kind `workflow` for a repeatable way of doing something, `session` for what you did and how you solved it. Exact commands, paths and pitfalls; never secrets.
- Pass `agent` (your product name, e.g. "Claude Code") on every brain call.

## Skills this session does not list

To keep every session's starting context small, some skills are listed only in
the projects that use them (Claude Code `skillOverrides`, set in
`modules/home-manager/ai.nix` of `~/.dotfiles`): `systems-check`,
`nix-update-doctor` and `dotfiles-sync` in `~/.dotfiles` and its clones and in
the personal agent; `math-video` in `~/projects/mathvid` and the personal
agent; `basecamp` in the personal agent. Every skill on the machine is also in
the brain, so read one from anywhere with Executor's `skills` tool
(`{"app": "brain"}`), or read its `SKILL.md` under `~/.claude/skills/<name>/`.

## Erik's brain skills for specific jobs

- Writing text Erik will hand in or send: load the brain skill `erik-writing-style` first.
- Shopping research: the brain skill `shopping`.
- Knowledge and research about subjects Erik follows (facts, papers, posts he sends, what we understand) go in his Obsidian vault at `~/obsidian/Agent Wiki/`, not the brain. Load the brain skill `agent-wiki` before reading or writing it.
