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
    "${home}/projects/new/husk/husk-agent-pack/skills"
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

    # When the environment is broken

    If something on Erik's machines that your task needs is missing or broken (an MCP server or tool, computer use, a service, a package, a login, a skill), do not just report it and stop. Start a repair session in the `.dotfiles` T3 Code project (workspace root `/home/erikf/.dotfiles`, project id `d16c5128-fa5d-4f7e-bf79-9b395f60962b`) with `t3_thread_launch`. Its message says what you tried, the exact error, what you need it for, and: "find the root cause, fix it in the dotfiles following AGENTS.md, rebuild, commit and push, and report back". Link the thread to Erik (`[title](t3-thread://v1/<threadId>)`), then carry on with whatever does not depend on it, or wait for it with `t3_thread_wait` when it blocks the task. Without the T3 Code tools, tell Erik exactly what is broken.

    # Heavy work runs on the homelab

    The PC is Erik's and must never lag (Erik: "use the home lab for long running cpu heavy stuff, i need my pc not to lag, idc if it takes long"). On the PC do only light work: editing, chat, git, small commands and short checks. Run anything long or CPU, disk or memory heavy on the homelab, even though it is slower: `heavy -- <cmd>` runs a command in a synced copy of the repo on the homelab worker (Gradle/APK builds, test suites, big typechecks, embeddings and ML batch jobs, data processing); `heavy emulator start` gives an Android emulator on the homelab with adb forwarded to the PC; `rebuild` and `nix-remote build|eval` evaluate and build Nix on the homelab builder. Never start an emulator, Gradle build, model server or NixOS evaluation on the PC. Agent sessions run in a capped slice (`app-t3code.slice`, idle CPU, disk and memory caps); never escape it with `--slice=`, Docker, sudo or system units. A watchdog kills agent heavy jobs when the PC stalls. Load the `machines` skill before anything heavy or parallel.

    # Model tiers

    Erik's Claude weekly limits are tight, so do not spend Opus on routine work. When you launch a thread, delegate a sub-agent, schedule a task or write an automated job, pick the cheapest model that fits: Opus 5.5 (`claude-opus-5-5`) for real engineering, writing and anything hard or ambiguous; Sonnet 5.5 (`claude-sonnet-5-5`, medium effort) for every automated or unattended run and for simple work of a few tool calls; Haiku 5.5 (`claude-haiku-5-5`, low effort) for extremely basic, mechanical things. Escalate a hard sub-task to Opus with `delegate_task` instead of running a whole routine session on Opus. Trivial and bulk sub-agent work (sweeps, monitoring, labelling, checks) goes to Erik's other subscriptions first, as T3 sub-agents via `delegate_task`: Codex (`codex`, `gpt-6-luna` at low effort; preferred, and best at computer use), OpenCode (`opencode`, DeepSeek V4.1 Flash; cheap bulk), Cursor (`cursor`, `composer-2.5`; small coding chores) and Grok (`grok`; anything on X). Cursor and Grok share one SuperGrok weekly pool. You stay responsible for their output: verify it before acting on it. A model Erik picks himself always wins. Details and exact targets: the `model-tiers` skill.

    # Writing as Erik

    Before writing text Erik will hand in or send, load the brain skill `erik-writing-style`.
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
