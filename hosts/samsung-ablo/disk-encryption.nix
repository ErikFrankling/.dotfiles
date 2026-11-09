# Disk encryption. NixOS is on LUKS2 (cryptroot, hardware-configuration.nix);
# Windows, on the same disk, has BitLocker.
#
# The TPM unlocks the disk at boot, as BitLocker does for Windows, so the
# laptop can boot on its charger and take the nightly update unattended. The
# key is sealed to PCR 7 (Secure Boot on, with our keys): booting anything not
# signed by them gets the passphrase prompt instead. NixOS wiki, "Full Disk
# Encryption" > TPM2. One-time, after Secure Boot is on (README.md):
#
#   sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/nvme0n1p5
{
  boot.initrd.luks.devices.cryptroot.crypttabExtraOpts = [ "tpm2-device=auto" ];

  # Graphical boot, and a graphical passphrase prompt when the TPM says no.
  boot.plymouth.enable = true;
}
