# SOC 2 endpoint controls for the samsung-ablo laptop, one file each.
# README.md has the commands that show each one to an auditor.
#
# Vanta's Device Monitor does not support NixOS and on Linux only checks disk
# encryption, so these are shown with manual evidence (help.vanta.com
# 11345596). Research: ~/projects/ablo/research/.
{
  imports = [
    ./disk-encryption.nix
    ../../modules/nixos/screen-lock.nix
    ../../modules/nixos/fingerprint.nix
    ./keyring.nix
    ../../modules/nixos/antivirus.nix
    ./vanta.nix
    ../../modules/nixos/1password.nix # password manager
  ];

  # The weekly malware scan covers the whole disk (Erik, 2026-11-13), not the
  # NixOS module's default list (/home /var/lib /tmp /etc /var/tmp), which
  # missed /root, /var/log, /var/vanta, /boot and /nix/store. /proc, /sys,
  # /dev and /run are left out in antivirus.nix (ExcludePath).
  services.clamav.scanner.scanDirectories = [ "/" ];

  # Firewall: the NixOS default (on). Patching: the daily auto-update
  # (configuration.nix). Secure Boot: modules/nixos/secure-boot.nix.
}
