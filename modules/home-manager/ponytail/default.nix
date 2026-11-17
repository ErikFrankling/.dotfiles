{ lib, ... }:
let
  skills = [
    "ponytail"
    "ponytail-review"
    "ponytail-audit"
    "ponytail-debt"
  ];
in
{
  # Ponytail for every harness: the smallest complete change, as Ablo's
  # AGENTS.md uses it. Vendored unchanged from
  # https://github.com/DietrichGebert/ponytail at 96608e078b2d5ea607c5c3b8b5a54d1c1fba6846
  # (MIT), except that each SKILL.md description is cut to one line (every
  # session lists every description; Erik, 2026-11-17). Only the SKILL.md
  # files and LICENSE; the upstream hooks, statusline, plugins and install
  # scripts are not used. Skipped: ponytail-gain (benchmark
  # scoreboard) and ponytail-help (documents those hooks and their config).
  home.file = lib.mergeAttrsList (
    lib.concatMap (dir: map (skill: { "${dir}/${skill}".source = ./skill/${skill}; }) skills) [
      ".agents/skills"
      ".claude/skills"
      ".codex/skills"
    ]
  );
}
