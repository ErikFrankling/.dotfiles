---
name: model-tiers
description: Which model, provider and reasoning effort to use for a session, a delegated sub-agent or a scheduled task on Erik's machines. Claude (Opus 5.5, Sonnet 5.5, Haiku 5.5) is the default for everything; OpenCode, Grok and Codex are small plans for one job each; Fable is the second opinion. Load before launching a thread, delegating a task, scheduling a recurring task or writing an automated job, and when choosing the model for one.
---

# Model tiers

Claude is the default for everything: interactive work, automated runs, trivial
and bulk sub-agent work, second opinions. Erik has a very big Claude token
budget. The same IDs exist on both Claude accounts (`claudeAgent` and
`claudeAgent_claude_2`), so pick the model here and leave the account choice
to whatever is in place (account failover is handled separately, and limits can
still hit: when one does, let failover or `t3_thread_limit_recovery` handle it).

## The tiers

| Model | Effort | Use it for |
| --- | --- | --- |
| `claude-opus-5-5` | medium (default); high/xhigh only for a genuinely hard problem | Real engineering: non-trivial code, debugging something not understood yet, writing Erik will read, anything hard, ambiguous or high-stakes, orchestrating other agents. |
| `claude-sonnet-5-5` | medium | Simple work along a known path (run a command and report, follow a skill, small edits, triage logs) and automated or unattended runs where it is enough: nightly update, morning check, health incident, scheduled tasks, dotfiles sync. |
| `claude-haiku-5-5` | low | Mechanical work: reformat, rename, classify, extract a field, check one status, relay a message. |
| `claude-fable-5-1` | medium | A second opinion or separate perspective on a plan, a design or a diff. |

## Other providers: one job each

Erik has small plans on everything except Claude. They are not for general,
trivial or bulk work; do not suggest them for it. Each runs as a T3 sub-agent
with `delegate_task` and a `target` (`orchestrator_capabilities` is the live
list):

| Provider | `target` | Use it only for |
| --- | --- | --- |
| **OpenCode** | `{"providerInstanceId":"opencode","model":"opencode-go/deepseek-v4.1-flash","options":{"variant":"low"}}` | Sensitive work such as cyber security; Chinese models are good at it. |
| **Grok** | `{"providerInstanceId":"grok","model":"grok-4.7"}` | Looking at Twitter/X: posts, people, threads. |
| **Codex** | the Codex provider | Image generation. |

Cursor is also a small plan; use it only if Erik picks it. Any of them could
give a second opinion, but Fable is the default for that.

## Rules

- **Erik decides when he says so.** A model Erik picks always wins.
- **Automated runs** (timers, scheduled tasks, webhooks, health-watch
  incidents) default to Sonnet 5.5 at medium effort, declared where the job is
  defined (Nix option, launcher script, `--model` on headless `claude`), not by
  hand in the UI. Use Opus where the job is real engineering.
- **Escalate the part, not the session.** When a Sonnet run hits something
  hard (a build failure it cannot explain, a design decision), delegate that
  sub-task to Opus with `delegate_task` after one honest failed attempt.
- **Sub-agents** get the model that fits: Haiku or Sonnet for search, log
  collection, sweeps and labelling; Opus for reviews of real code and real
  features. Write the brief so the model can do it: exact paths, the goal,
  what done means, and "do not change anything" when it is read-only. Check a
  child's output before acting on it.
- **Effort:** set it explicitly when delegating; a child should not inherit a
  high one. Use high/xhigh only when the task is known to be hard, never max.
- **Scheduled tasks** run on the model of the thread they post into. Bind a
  routine one to a Sonnet (or Haiku) thread; if it must post into an Opus
  thread, keep the prompt short and let it do the work itself or delegate it to
  a Claude child.
- Computer use goes to a Claude agent.

## Where it is applied

- Nightly update, morning check, health incident:
  `autoUpdateNightly.modelSelection` in
  `modules/home-manager/auto-update/default.nix` (Sonnet 5.5, medium), also
  used for their headless fallback.
- Dotfiles sync before the 06:00 update: `modules/nixos/auto-update.nix`
  (`claude --model claude-sonnet-5-5`).
- The personal agent's hourly session sweep (T3 scheduled task
  `hourly-session-sweep-1021`, app state, not Nix): does its scan itself, on
  Claude.
- This skill and the one-paragraph global rule:
  `modules/home-manager/company-brain.nix`.
