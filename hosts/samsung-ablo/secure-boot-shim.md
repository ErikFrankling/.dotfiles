# Secure Boot on Galaxy Book6 Pro (PRHK)

Firmware PRHK.1.4.56.576 has not exposed a confirmed custom-key enrollment
procedure. Removing Windows does not resolve that limitation. Keep the factory
keys, Windows loader, fallback loader and recovery partition.

`shim.nix` stages Microsoft's signed Fedora shim 16.1-10 and its MokManager in
`/boot/EFI/nixos-shim`, alongside a copy of Lanzaboote's signed systemd-boot
(named `grubx64.efi`, the filename shim loads). The copy refreshes on every
`rebuild boot`/`switch`. The original Lanzaboote installer remains unchanged.
The added `NixOS (shim)` firmware entry does not change BootOrder or BootNext.
A pre-staging ESP archive and boot-entry listing live under
`/var/lib/sbctl/pre-shim-backup` (root only). No private key goes onto the ESP.

## Validation, 2026-11-10

Isolated OVMF, populated with this laptop's actual public db and dbx, used a
disposable test MOK and the same systemd262 EFI binary as the laptop, followed
by Lanzaboote1.1.0 and a NixOS kernel6.18.62/tiny test initrd:

- Valid chain booted; kernel reported Secure Boot enabled.
- Changed external kernel rejected with hash mismatch / SECURITY_VIOLATION.
- Changed external initrd rejected with hash mismatch / SECURITY_VIOLATION.
- Removing test MOK rejected systemd-boot in shim with Security Violation.

This proves compatibility of the chain with those trust/revocation lists in
OVMF, not physical Samsung firmware behavior or Windows BitLocker behavior.
Test evidence on PC: `/home/erikf/projects/personal/shim-validation/VALIDATION.md`
and `evidence.txt`. Test keys must never be enrolled on the laptop.

Community report: https://github.com/nix-community/lanzaboote/issues/165#issuecomment-3368549643
Lanzaboote does not officially support shim:
https://github.com/nix-community/lanzaboote/issues/165#issuecomment-4206514776

## Physical enrollment and first test

Only after verifying staged signatures, backup and unchanged BootOrder:

1. In the laptop terminal: `sudo mokutil --import /boot/EFI/nixos-shim/db.cer`.
   Choose a temporary enrollment password locally. Do not send it in chat.
2. Reboot when ready and select **NixOS (shim)** from the one-time boot menu.
   Keep Secure Boot disabled for this enrollment pass.
3. In MokManager choose **Enroll MOK**, **Continue**, **Yes**, enter that
   temporary password, and reboot. This adds our existing signing certificate
   to shim's MOK list, not to the firmware's PK/KEK/db.
4. Boot NixOS normally and verify
   `sudo mokutil --test-key /boot/EFI/nixos-shim/db.cer` reports enrolled.
5. Then enable Secure Boot in firmware and select **NixOS (shim)** again.
   The default remains the old loader until the test is confirmed. If firmware
   instead tries that old loader, select the prepared shim entry manually.
6. Check `bootctl status`, `mokutil --sb-state`, and the kernel boot log.
   Only after a successful physical boot make the shim entry the default.

Have the Windows BitLocker recovery key available before changing Secure Boot;
changed boot measurements can trigger recovery. Do not clear TPM, enable
platform erase, delete ESP contents, or replace factory keys. If the shim test
fails, disable Secure Boot and select the existing Linux Boot Manager; the
Windows Boot Manager and normal Linux entry remain present.

## Physical result and TPM enrollment, 2026-11-10

Verified on the laptop: `SecureBoot enabled`, `BootCurrent: 0001`,
`BootOrder: 0001,0000,0002`, enrolled db.cer, systemd-boot262 loaded from
`/EFI/nixos-shim/grubx64.efi`, lanzastub1.1.0. The Samsung BIOS dropdown
omitted entry0001 while it was outside BootOrder. Adding it first with
`sudo efibootmgr --bootorder 0001,0000,0002` made the successful boot possible.
Keep both original entries. A direct boot through entry0000 does not export
shim's runtime MOK list, so a negative mokutil test there is not evidence
that enrollment was lost. Verify through shim before enrolling again.

TPM key slot1 was enrolled with `systemd-cryptenroll --tpm2-device=auto
--tpm2-pcrs=7+14 /dev/nvme0n1p5` after this verified Secure Boot. PCR7 binds
firmware policy; PCR14 also binds shim/MOK policy. Existing password slot0
remains. A root-only pre-enrollment header backup is at
`/var/lib/sbctl/pre-shim-backup/luks-header-before-tpm.img`.

Non-disruptive token-only unlock passed:
`sudo env LD_LIBRARY_PATH=/run/current-system/sw/lib/cryptsetup cryptsetup
open --test-passphrase --token-only /dev/nvme0n1p5`.
The library path is needed for this standalone cryptsetup test on NixOS;
systemd in initrd already provides its TPM integration. No disk mapping was
opened or mounted by the test. Full automatic startup still needs a physical
reboot test; keep the recovery password for changed firmware/key policy.
