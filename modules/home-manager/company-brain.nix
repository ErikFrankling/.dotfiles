# The company brain (https://brain.erikfrankling.duckdns.org): workflows, skills
# and session reports every agent searches before a task and publishes to after
# it, reached through the Executor app `brain`. This module tells Claude Code
# and Codex to use it, and keeps its skills in step with this machine.
#
# Every skill directory the harnesses load is imported into the brain as a
# `skill` entry; the brain's Executor app serves those to every agent through
# Executor's `skills` tool. Unchanged skills are skipped, so the timer is cheap. The importer lives with
# the brain's source (agent-company repo, apps/brain/bin/import-skills.mjs).
{
  config,
  osConfig,
  pkgs,
  lib,
  ...
}:
let
  home = config.home.homeDirectory;
  importer = "${home}/projects/agent/apps/brain/bin/import-skills.mjs";
  # Most specific first: the first directory that provides a skill name wins.
  skillDirs = [
    "${home}/.claude/skills"
    "${home}/.codex/skills"
    "${home}/.agents/skills"
    # "${home}/projects/new/husk/husk-agent-pack/skills" # retired Husk imports
  ];
  # Global instructions for every Claude Code and Codex session (T3 Code's Codex
  # uses its own CODEX_HOME, ~/.codex-t3).
  instructions = ''
    # Company brain

    Erik's agents share a company brain: workflows, skills and session reports about how things are done on his machines and in his company (home lab, NixOS, X/Twitter, explainer videos, creative work, deploys). It is the Executor app `brain`: tools `tools.brain.search`, `read`, `publish`, `feedback` and `recent` (call them through the executor MCP server), and every saved skill is readable with Executor's `skills` tool (`{"app": "brain"}`).

    - Before a task that touches this environment, or that someone here has probably done before, search the brain with the task in a few words, read the best match and follow it unless the user says otherwise.
    - After following an entry, call `feedback` with worked, failed or outdated and a one-line note.
    - After solving something non-obvious, `publish` it (or update the entry you followed by passing its id): kind `workflow` for a repeatable way of doing something, `session` for what you did and how you solved it. Exact commands, paths and pitfalls; never secrets.
    - Pass `agent` (your product name, e.g. "Claude Code") on every brain call.

    # Never contact other people

    Never send, post, reply, react, comment, invite, share or connect with any other person on Erik's behalf (Discord, LinkedIn, X, email, Teams, SMS, GitHub comments, connect.husksecurity.dev invites, shared docs, links), unless Erik approved that exact message in this conversation. Drafts for Erik to send himself are fine. Notifications to Erik himself are fine. Erik: "I don't want anyone to receive any AI slop from me."

    # Finish what Erik asked

    Finish what Erik asked, all the way to live. Don't stop to ask permission for things inside his request: deploying to production, merging to main, migrating data after a verified backup, publishing app builds, changing homelab or dotfiles config. Pick sensible defaults and state them in your report. Stop only for something irreversible with no backup, something needing Erik physically (a login or phone tap), or contacting other people (see the rule above). "Done" means live and proven (screenshots, logs, URLs), not "ready on a branch".

    # Agent traces are never deleted

    Erik (2026-11-12): "Never ever get rid of agent traces, they are very valuable." Agent traces are every transcript, session log and run output of any agent: `~/.claude/projects`, `~/.claude_2`, `~/.codex/sessions`, `~/.codex/archived_sessions`, `~/.codex*/*.sqlite`, `~/.codex-t3`, `~/.t3/userdata`, `~/.local/share/opencode`, `~/.grok`, `~/.omp`, `~/agent-traces`, and agent output inside projects or data folders (`codex exec --json` JSONL, prompts, stdout/stderr logs, outcomes, run logs). No cleanup, disk emergency or retention setting deletes, truncates, prunes or rewrites them. When a folder that holds traces must go, copy the traces to `~/agent-traces/<project>/` first and verify the copy.

    # Clean up after yourself

    Every worktree, clone or scratch checkout you create, you remove once its work is merged or pushed and no longer needed (`git worktree remove`, delete the merged branch, and its per-worktree build output with it). Abandoned worktrees with their own `target/` and `node_modules` filled both of Erik's drives in 2026-11. Leave only unfinished work, and say where it is. Scheduled sessions also sweep what earlier runs left: the `housekeeping` skill.

    # Never end a turn while waiting

    Ending a turn means your final report has been sent. Never end a turn while you wait on something you started or need (a build, deploy, test run, idle gate, CI, another session): "waiting for the heavy build", "the monitor is armed, I'll report when…" and "I'll check later" leave the work stuck, because nothing re-invokes you. Wait inside the turn: poll at a sensible interval with a cap (up to 45-60 minutes), then continue. If the wait is longer, finish what you can and report to whoever asked (`t3_thread_send` to the personal agent when it briefed you) what is pending and what will pick it up. Rely only on a mechanism that really re-invokes you (a T3 scheduled task or `ScheduleWakeup` that fires, a monitor the harness tracks).

    # When the environment is broken

    If something on Erik's machines that your task needs is missing or broken (an MCP server or tool, computer use, a service, a package, a login, a skill), do not just report it and stop. Start a repair session in the `.dotfiles` T3 Code project (workspace root `/home/erikf/.dotfiles`, project id `d16c5128-fa5d-4f7e-bf79-9b395f60962b`) with `t3_thread_launch`. Its message says what you tried, the exact error, what you need it for, and: "find the root cause, fix it in the dotfiles following AGENTS.md, rebuild, commit and push, and report back". Link the thread to Erik (`[title](t3-thread://v1/<threadId>)`), then carry on with whatever does not depend on it, or wait for it with `t3_thread_wait` when it blocks the task. Without the T3 Code tools, tell Erik exactly what is broken.

    # Long jobs go to the homelab

    Erik's PC has a fast CPU: compile, build, typecheck and test on it as usual. What he minds is something hogging it for minutes (Erik: "of course you can compile things locally, I have a very fast CPU, let's use it; just if this takes 10 min, consider offloading"). So anything expected to take ~10+ minutes, or that turns out to, runs on the homelab: `heavy -- <cmd>` (big Gradle/APK release builds, long test suites, embedding and ML batches, data processing), `heavy emulator start` for an emulator you need for long, `nix-remote` or `rebuild --remote` for long Nix builds. Agent sessions run in a capped slice (`app-t3code.slice`: 4 cores, memory and disk caps); never escape it with `--slice=`, Docker, sudo or system units. A watchdog kills agent jobs that keep the CPU busy for 5+ minutes or stall Erik's desktop, and tells you to re-run them with `heavy`. Exception, max mode: when Erik says he is away from the PC, run `agent-max on` (14 of 16 CPUs, 22/25 GB RAM, the watchdog stops killing long jobs; it switches itself off when he touches a keyboard or mouse, or after 12 h). Check `agent-max status` (exit 0 = on) before running long work locally; when it is off, use `heavy`. Max mode is the only allowed way past the caps. Details: the `machines` skill.

    # Model tiers

    Claude is the default for everything, including trivial, bulk and sub-agent work; Erik has a very big Claude token budget. Opus 5.5 (`claude-opus-5-5`) for real engineering and anything hard; Sonnet 5.5 (`claude-sonnet-5-5`) or Haiku 5.5 (`claude-haiku-5-5`) for simple or mechanical work and for automated runs where they are enough. For a second opinion or a separate perspective, use Fable (`claude-fable-5-1`). Erik has small plans on the other providers, each used for one job and not for general work: OpenCode for sensitive work such as cyber security (Chinese models are good at it), Grok for looking at Twitter/X, Codex for image generation. Cursor is also a small plan; use it only if he picks it. A model Erik picks himself always wins. Details and exact targets: the `model-tiers` skill.

    # Writing as Erik

    Before writing text Erik will hand in or send, load the brain skill `erik-writing-style`.

    # Shopping

    For shopping research, load the brain skill `shopping`.
  '';
  # Skills that ship with this module, installed for every harness.
  skills = {
    model-tiers = ./model-tiers;
  };

  sync = pkgs.writeShellApplication {
    name = "brain-skill-sync";
    runtimeInputs = [ pkgs.nodejs ];
    text = ''
      if [ ! -r ${lib.escapeShellArg importer} ]; then
        echo "brain-skill-sync: ${importer} is missing; nothing to do" >&2
        exit 0
      fi
      BRAIN_TOKEN="$(< ${osConfig.sops.secrets.brain-token.path})"
      export BRAIN_TOKEN
      export BRAIN_URL=https://brain.erikfrankling.duckdns.org
      export BRAIN_ACTOR="skill sync (${osConfig.networking.hostName})"
      exec node ${lib.escapeShellArg importer} ${lib.escapeShellArgs skillDirs}
    '';
  };
in
{
  home.packages = [ sync ];

  # Remove only the manually installed Husk skill links, never repository code
  # or independently installed skills. Keep the personal Brain service.
  home.activation.retireHuskSkillLinks = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    for dir in "$HOME/.agents/skills" "$HOME/.claude/skills" "$HOME/.codex/skills" "$HOME/.codex-t3/skills"; do
      for skill in husk-company-context husk-document-work; do
        link="$dir/$skill"
        if [ -L "$link" ] && [ "$(readlink "$link")" = "$HOME/projects/new/husk/husk-agent-pack/skills/$skill" ]; then
          $DRY_RUN_CMD rm "$link"
        fi
      done
    done
  '';

  home.file = {
    ".claude/CLAUDE.md".text = instructions;
    ".codex/AGENTS.md" = {
      text = instructions;
      # Codex left an empty file here.
      force = true;
    };
    ".codex-t3/AGENTS.md".text = instructions;
  }
  // lib.mergeAttrsList (
    lib.mapCartesianProduct ({ dir, skill }: { "${dir}/${skill}".source = skills.${skill}; }) {
      dir = [
        ".agents/skills"
        ".claude/skills"
        ".codex/skills"
      ];
      skill = builtins.attrNames skills;
    }
  );

  systemd.user.services.brain-skill-sync = {
    Unit.Description = "Import local agent skills into the company brain";
    Service = {
      Type = "oneshot";
      ExecStart = lib.getExe sync;
    };
  };

  systemd.user.timers.brain-skill-sync = {
    Unit.Description = "Import local agent skills into the company brain";
    Timer = {
      OnBootSec = "5min";
      OnUnitActiveSec = "30min";
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
