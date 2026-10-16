{ lib, ... }:
{
  # The machines skill for every harness: which machines Erik has, how to
  # reach them, and how much load the pc can take before it swaps.
  home.file = lib.mergeAttrsList (
    map (dir: { "${dir}/machines".source = ./skill/machines; }) [
      ".agents/skills"
      ".claude/skills"
      ".codex/skills"
    ]
  );
}
