{ lib, ... }:
{
  # The phone-preview skill for every harness on the PC. The proxy it describes
  # is ../../nixos/dev-preview.nix; the skill only makes sense where that runs.
  home.file = lib.mergeAttrsList (
    map (dir: { "${dir}/phone-preview".source = ./skill/phone-preview; }) [
      ".agents/skills"
      ".claude/skills"
      ".codex/skills"
    ]
  );
}
