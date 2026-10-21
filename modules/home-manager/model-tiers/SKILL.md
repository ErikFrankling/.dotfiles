---
name: model-tiers
description: Which model, provider and reasoning effort to use for a session, a delegated sub-agent or a scheduled task on Erik's machines (Opus 5.5 vs Sonnet 5.5 vs Haiku 5.5, and Codex, Grok and OpenCode sub-agents for trivial or bulk work). Load before launching a thread, delegating a task, scheduling a recurring task or writing an automated job, and when choosing the model for one.
---

# Model tiers

Erik has two Claude subscriptions and keeps hitting both weekly limits. Opus
is for work that needs it; everything routine runs on something cheaper. The
same IDs exist on both Claude accounts (`claudeAgent` and
`claudeAgent_claude_2`), so pick the model here and leave the account choice
to whatever is in place (account failover is handled separately).

## The tiers

| Tier | Model | Effort | Use it for |
| --- | --- | --- | --- |
| Hard | `claude-opus-5-5` | medium (default); high/xhigh only for a genuinely hard problem | Real engineering: designing or writing non-trivial code, debugging something not understood yet, writing Erik will read, anything ambiguous or high-stakes, orchestrating other agents. |
| Routine | `claude-sonnet-5-5` | medium (its default is high; lower it) | Every automated or unattended run: nightly update, morning check, health incident, scheduled tasks, dotfiles sync. Interactive work that is a few tool calls along a known path: run a command and report, follow a skill step by step, small edits, look something up, triage logs. |
| Trivial | `claude-haiku-5-5` | low | Extremely basic, mechanical work: reformat, rename, summarize a short text, classify, extract a field, check one status, relay a message. |

## Other subscriptions: Codex, Grok, OpenCode

Erik also pays for Codex, Grok and OpenCode. Their usage does not touch the
Claude limits, so trivial and bulk sub-agent work goes there first. Every one
runs as a T3 sub-agent with `delegate_task` and a `target`, and their children
have the same `t3-code` tools, so they can delegate further (sub-sub-agents)
and read or steer T3 threads. `orchestrator_capabilities` is the live list.
The IDs below were each tested with a real `delegate_task` on 2026-10-21.

| Provider | `target` | Use it for |
| --- | --- | --- |
| **Codex** (preferred, the strongest of the three) | `{"providerInstanceId":"codex","model":"gpt-6-luna","options":{"reasoningEffort":"low"}}` for routine work; `"model":"gpt-6.1-sol"` (low or medium) when it needs more brains | The default non-Claude sub-agent: sweeps and status checks over T3 threads, log triage, small scripted chores, code review as a second opinion, and computer use (best at it). |
| **Grok** | `{"providerInstanceId":"grok","model":"grok-4.7"}` for research; `"grok-4.7-build-fast"` (`"options":{"reasoningEffort":"low"}`) or `"grok-build"` for quick builds | Anything on X/Twitter (posts, people, threads; it is the best at X lookups), plus quick throwaway build tasks. |
| **OpenCode** | `{"providerInstanceId":"opencode","model":"opencode-go/deepseek-v4.1-flash","options":{"variant":"low"}}` (Go subscription); free: `"opencode/deepseek-v4.1-flash-free"`, `"opencode/glm-5.3-flash-free"` | Fast, cheap bulk: monitoring, labelling or classifying data, many small trivial checks. DeepSeek V4.1 Flash gives a lot of tokens for almost nothing. |

Rules for these:

- **You stay responsible.** They are for trivial or bulk work where a wrong
  answer is cheap to catch, not for work that has to be right the first time.
  Check their output before acting on it or reporting it: spot-check a sample
  of labels, re-read the one thread a sweep says failed, run the test
  yourself. Never let one push, deploy, delete or message Erik unchecked.
- **Order of preference** for a trivial sub-task: Codex → OpenCode → Grok
  (Grok first for anything on X). Fall back to Claude Haiku/Sonnet only when
  none of them fits or they are failing.
- **Brief them fully.** A child gets only your task text: give exact paths,
  IDs, commands, the output format you want, and "do not change anything" when
  it is read-only.
- **If a provider errors** (expired key, out of quota), switch to the next one
  and start a repair session for the broken one as the global rule says.
- **Schedules:** a recurring routine (hourly sweep, monitor, import) should
  delegate its work to one of these instead of running on Claude, e.g. the
  personal agent's hourly session sweep delegates to Codex `gpt-6-luna`.

## Rules

- **Automated means Sonnet.** A session nobody watches (timers, scheduled
  tasks, webhooks, health-watch incidents) starts on Sonnet 5.5 at medium
  effort. Declare that where the job is defined (Nix option, launcher script,
  `--model` on headless `claude`), not by hand in the UI.
- **Escalate the part, not the session.** When a Sonnet run hits something
  hard (a build failure it cannot explain, a design decision), delegate that
  one sub-task to Opus with `delegate_task` and carry on, rather than running
  the whole thing on Opus. Escalate after one honest failed attempt, not
  before.
- **Sub-agents get the cheapest model that fits.** Search, file reading,
  "find where X is", collecting logs, sweeps, labelling: Codex, OpenCode or
  Grok first (next section), else Haiku or Sonnet. Reviews of real code
  and implementation of real features: Opus. Write the brief so a smaller
  model can do it: exact paths, the goal, what done means.
- **Effort before model.** Raising effort on a small model is cheaper than
  jumping a tier; lowering effort on Opus for an easy step is cheaper than
  keeping it at high. Use high/xhigh only when the task is known to be hard,
  never max, and never leave ultrathink/ultracode on for routine work. Set
  effort explicitly when delegating; a child should not inherit a high one.
- **Scheduled tasks** run on the model of the thread they post into. Bind a
  routine scheduled task to a thread that is set to Sonnet (or Haiku for a
  trivial relay), not to an Opus working thread. If it must post into an Opus
  thread (e.g. the personal agent), keep the prompt short and let it delegate
  the actual work to a Sonnet child.
- **Erik decides when he says so.** If Erik picks a model for a thread, use
  it. This policy is the default, not an override.

## Where it is applied

- Nightly update, morning check, health incident:
  `autoUpdateNightly.modelSelection` in
  `modules/home-manager/auto-update/default.nix` (Sonnet 5.5, medium), also
  used for their headless fallback.
- Dotfiles sync before the 06:00 update: `modules/nixos/auto-update.nix`
  (`claude --model claude-sonnet-5-5`).
- The personal agent's hourly session sweep (T3 scheduled task
  `hourly-session-sweep-1021`, app state, not Nix): delegates to Codex
  `gpt-6-luna`, falling back to OpenCode free DeepSeek Flash.
- This skill and the one-paragraph global rule:
  `modules/home-manager/company-brain.nix`.

## What Theo says (t3.gg, maker of T3 Code), and how it shaped this

Collected 2026-10-21. His view is coder-centric (Opus by default) and that is
kept here: Sonnet is only for routine runs, never as a cheaper coder.

- **Coding gets the smartest model; categorization gets the cheapest one that
  works.** "If coding, use smartest model you can … For data processing,
  categorization, etc, use the cheapest thing that gets you the results you
  want." (2026-08-05, https://x.com/theo/status/2084861440348020790)
  → Opus for engineering; Haiku for mechanical work.
- **Sonnet 5.5 is not a cheaper Opus for real code.** Agent cost is mostly
  cache reads, and for like-for-like coding Sonnet came out as expensive as
  Opus or more: "Sonnet 5.5 is an incredible model. You probably shouldn't
  use it." (2026-09-29, https://x.com/theo/status/2104837275914002820,
  https://www.youtube.com/watch?v=8WbW_n95wc4&t=653s)
  → Do not move engineering to Sonnet to save limits. Sonnet is for runs that
  follow a known path (a skill, a checklist, a few commands).
- **A cheap model that flails costs more than Opus.** "If Opus can solve a
  problem in 100k tokens, and Haiku burns a million before it figures out it
  can't, Haiku ends up more expensive." Haiku is for short sub-agent and tool
  work: file search, categorization, checks. (2026-10,
  https://www.youtube.com/watch?v=38_6C0dkKmU&t=2171s)
  → Escalate after one honest failed attempt; keep Haiku on short tasks.
- **Never max effort.** "Max isn't just making it so the model can think more,
  it is removing its ability to think less." Max gained 1 point at about 13×
  the cost on his benchmark. (2026-09-25,
  https://www.youtube.com/watch?v=ejjBbaq9RmY&t=739s)
  → Max is off-limits; high/xhigh only for known-hard work.
- **Sub-agents must not inherit the parent's top effort.** On children
  inheriting ultra: "Causes massive token burn for no good reason. At the very
  least, I should be able to hard-set the subagent effort level to 'medium'."
  (2026-07-11, https://x.com/theo/status/2075742083370127504)
  → Set effort explicitly on every delegation; medium unless the sub-task is
  known to be hard.
- **Do not over-optimize.** "Opus orchestrating opus is fine and reasonably
  priced." (2026-09-25, https://x.com/theo/status/2103384380282655189)
  → For real engineering, an Opus child is fine; the savings come from
  routine and unattended runs, not from starving hard work.
- **GPT-6.1 Sol for reviews, architecture and computer use; Opus for code.**
  "I absolutely default to it for code reviews, architecture analysis,
  computer use, email management…" (2026-09-29,
  https://x.com/theo/status/2105001138953327067)
  → Codex is the preferred second-opinion and computer-use sub-agent.
- **The weekly cap is the tight one.** Claude Max "20x" is mostly the 5-hour
  window; the weekly limit is only about 2× more. (2026-09-28,
  https://x.com/theo/status/2104688105983008906)
