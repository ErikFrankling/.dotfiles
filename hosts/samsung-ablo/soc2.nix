# SOC 2 endpoint controls for the samsung-ablo laptop, one file each.
# README.md has the commands that show each one to an auditor.
#
# Vanta's Device Monitor does not support NixOS and on Linux only checks disk
# encryption, so these are shown with manual evidence (help.vanta.com
# 11345596). Research: ~/projects/ablo/research/.
{
  imports = [
    ./disk-encryption.nix
    ./screen-lock.nix
    ./fingerprint.nix
    ./antivirus.nix
    ./vanta.nix
    ../../modules/nixos/1password.nix # password manager
  ];

  # Firewall: the NixOS default (on). Patching: the daily auto-update
  # (configuration.nix). Secure Boot: modules/nixos/secure-boot.nix.
}
