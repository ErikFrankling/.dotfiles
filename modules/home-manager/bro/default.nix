{ lib, ... }:
{
  # The /bro skill for every harness: re-explains the last answer (or pasted
  # text) in plain, casual language. Vendored unchanged from
  # https://github.com/luchasarie/bro-skill at 6c08e7ee5eb8ef8b9bf0588d400170654abc256b
  # (MIT). Only SKILL.md and LICENSE; the upstream install.sh is not used.
  home.file = lib.mergeAttrsList (
    map (dir: { "${dir}/bro".source = ./skill/bro; }) [
      ".agents/skills"
      ".claude/skills"
      ".codex/skills"
    ]
  );
}
