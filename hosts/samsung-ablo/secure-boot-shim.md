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

TPM disk auto-unlock remains a separate follow-up after this chain is proven.
