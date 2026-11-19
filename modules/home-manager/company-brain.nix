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
  # uses its own CODEX_HOME, ~/.codex-t3). Every session pays for every token
  # here (Erik, 2026-11-17: 100k+ tool calls a day), so this holds only the
  # rules that must hold everywhere, one line each, and points to the skill
  # with the details. Procedures belong in skills, which load only when needed.
  instructions = ''
    # Rules on Erik's machines

    - Never contact other people: send, post, reply, react, comment, invite or share nothing to anyone but Erik (Discord, X, LinkedIn, email, Teams, SMS, GitHub issues/PRs/comments, shared docs, links) unless Erik approved that exact message in this conversation. Drafts for him and notifications to him are fine.
    - Never delete, truncate, prune or rewrite agent traces (transcripts, session logs, run output: `~/.claude/projects`, `~/.codex*`, `~/.t3/userdata`, `~/agent-traces`, ...). Full list, and how to move them when a folder must go: `housekeeping` skill.
    - Authentication (sign-in, OAuth/SSO, MFA, passkeys, existing logins) only in the real agent Chromium (`browser` MCP, `browser-use` skill), never T3's built-in `preview_*`; run `agent-cookie-sync` before asking Erik to log in.
    - Claude is the default model for everything, sub-agents included; a model Erik picks wins. Which model or provider for what: `model-tiers` skill.
    - Finish what Erik asked all the way to live and proven, without asking for steps inside the request. Never end a turn while waiting on something you started; wait inside the turn. Details, long jobs (`heavy`), "small before big" and what to do when something on the machines is broken: `machines` skill.
    - Remove worktrees and clones you created once merged (`housekeeping` skill).
    - Link a file only by the absolute path where it is on disk right now (`ls` it first): a file made in a worktree or clone links into that worktree or clone, never into a main checkout that does not have it.
    - Company brain (search before a task here, publish after), Erik's writing style, shopping, Agent Wiki, and skills this session does not list: `company-brain` skill.
  '';
  # Skills that ship with this module, installed for every harness.
  skills = {
    model-tiers = ./model-tiers;
    company-brain = ./company-brain-skill;
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
