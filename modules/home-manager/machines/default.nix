{ lib, ... }:
{
  # Skills for every harness: machines (which machines Erik has, how to reach
  # them, how much load the pc can take before it swaps) and system-history
  # (what ran at a past time, per program, unit and T3 thread).
  home.file = lib.mergeAttrsList (
    lib.concatMap
      (dir: [
        { "${dir}/machines".source = ./skill/machines; }
        { "${dir}/system-history".source = ./skill/system-history; }
      ])
      [
        ".agents/skills"
        ".claude/skills"
        ".codex/skills"
      ]
  );
}
