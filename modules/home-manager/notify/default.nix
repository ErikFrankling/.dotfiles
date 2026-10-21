{ lib, ... }:
{
  # The notify skill for every harness: how agents send Erik a phone
  # notification or a one-time code. The CLI it describes is
  # ../../nixos/notify; the Executor app's source is ./executor-app.
  home.file = lib.mergeAttrsList (
    map (dir: { "${dir}/notify".source = ./skill/notify; }) [
      ".agents/skills"
      ".claude/skills"
      ".codex/skills"
    ]
  );
}
