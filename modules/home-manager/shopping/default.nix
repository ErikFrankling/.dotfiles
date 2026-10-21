{ lib, ... }:
{
  # The shopping skill for every harness: price research for Erik in Sweden
  # (Prisjakt first), per-unit math, and the Obsidian notes in
  # ~/obsidian/Life/shop/ai. Agents never buy anything themselves.
  home.file = lib.mergeAttrsList (
    map (dir: { "${dir}/shopping".source = ./skill/shopping; }) [
      ".agents/skills"
      ".claude/skills"
      ".codex/skills"
    ]
  );
}
