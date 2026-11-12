# TPM unlock of the LUKS root, once Secure Boot is on with our own keys
# (disk-encryption-plan.md, step 6). Without a TPM enrollment this does
# nothing and the passphrase prompt appears as before. Enrol with:
#
#   sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/disk/by-partlabel/framework-luks
#
# PCR 7 is the Secure Boot policy (our keys, Secure Boot on). Lanzaboote boots
# directly, without shim, so samsung-ablo's PCR 14 is not needed here.
{
  boot.initrd.luks.devices.cryptroot.crypttabExtraOpts = [ "tpm2-device=auto" ];

  # Graphical boot, and a graphical passphrase prompt when the TPM says no.
  boot.plymouth.enable = true;
}
