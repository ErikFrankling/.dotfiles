# Framework: disk encryption and Secure Boot plan

Erik asked (2026-11-12) for the same endpoint protection on the Framework as on
samsung-ablo. Screen lock, fingerprint and ClamAV are in `main` (`0ae53b2f`).
This file covers the rest: encrypting the root disk, Secure Boot and TPM
unlock. Nothing here has been run yet.

The ready config is on branch **`framework-luks-secureboot`**:

- commit 1: `hardware-configuration.nix` with root on LUKS2 (`cryptroot`, partition label `framework-luks`)
- commit 2: lanzaboote Secure Boot (`modules/nixos/secure-boot.nix`) and TPM unlock (`disk-encryption.nix`)

## Build proof (2026-11-12, homelab builder via `nix-remote build`)

Full `system.build.toplevel` builds, all on the homelab and in its cache:

| Commit | What | Output |
|---|---|---|
| `0ae53b2f` (main) | screen lock, fingerprint, ClamAV | `/nix/store/xbvq7rlwhiccla5szarshdp27yfvnrgk-nixos-system-framework-26.11.20261107.f4a03c0`; narinfo returns 200 from nix-cache |
| `c3c66f41` (branch, commit 1; built as `08d4837b` before a comment-only rebase) | + LUKS root | `/nix/store/vm72sdq7llqwx3ckjl9kh244cifbpxhk-nixos-system-framework-26.11.20261107.f4a03c0` |
| `573a52cb` (branch, commit 2; built as `dc8eb3cd`, out path re-evaluated identical after the rebase) | + lanzaboote and TPM unlock | `/nix/store/dkg4l680nnx5swigbry3d68sv6vpsrdv-nixos-system-framework-26.11.20261107.f4a03c0` |

Building only proves the configs evaluate and build. Whether they boot,
unlock and lock the screen on this hardware has not been tested.

## What is known about the machine

Source: the homelab Prometheus (Alloy node metrics). The last sample is from
**2026-11-11 18:59 CET**; the laptop has been offline since. Re-check
everything on the live machine in step 0.

| | Last known value |
|---|---|
| Model | Framework Laptop 13 (AMD Ryzen 7040), BIOS 03.20 |
| Disk | PNY CS2140 500 GB NVMe (`nvme0n1`) |
| `nvme0n1p1` | vfat `/boot` (ESP), 536 MB, 334 MB free |
| `nvme0n1p2` | ext4 `/` (UUID `26b10d70-…`), 459 GB, 111 GB free (~348 GB used, `/nix/store` included) |
| Swap | No disk swap; zram only (RAM, nothing written to disk) |
| RAM | 16 GB |
| NixOS | 26.11.20261107 (before `0ae53b2f`) |

**Not known from here:**

- whether the table is GPT (likely, since it's UEFI with systemd-boot)
- the TPM 2.0 state in the BIOS
- the current Secure Boot state
- `cryptsetup` behaviour on this disk

The config doesn't settle any of these.

## Options for encrypting the existing root

| Option | How | Verdict |
|---|---|---|
| **A. In place, offline** | From a live USB: shrink the ext4 by 32 MiB, then `cryptsetup reencrypt --encrypt --reduce-device-size 32M`. This is LUKS2 encryption with a data shift; the data stays where it is and the header goes at the start of the partition. | **Recommended.** It's supported by cryptsetup (man `cryptsetup-reencrypt`, "encryption with data shift"). No repartitioning or reinstall. The job is resilient: an interrupted run can be resumed with `cryptsetup reencrypt --resume-only`. It runs over all 459 GB, so plan for about an hour on AC power. |
| A'. In place, online | Encrypting the mounted, running root | Not possible. cryptsetup can only re-encrypt a device that is already LUKS while it's online; a plain mounted ext4 can't be switched over. |
| B. Reinstall | disko + LUKS like samsung-ablo, then restore `/home` from the backup | Cleaner and proven on samsung-ablo, but takes longer and relies fully on the restore. **Fallback** if A fails. |
| C. Encrypt only `/home` | fscrypt, or a separate LUKS volume | Rejected. `/etc/ssh`, `/var/lib`, Wi-Fi keys and logs would stay in clear text. |

Swap needs nothing: there is no disk swap, and zram lives in RAM. Hibernation
stays unavailable. If disk swap is ever added, put it inside `cryptroot`, as a
swapfile.

## Step 0: checks on the running laptop (an agent can do these over `ssh framework`)

```sh
lsblk -o NAME,SIZE,FSTYPE,PARTLABEL,PARTUUID,MOUNTPOINTS
sudo sgdisk -p /dev/nvme0n1          # must say GPT; note the root's partition number
df -h / /boot
bootctl status | grep -iE 'secure boot|tpm|setup mode'
systemd-cryptenroll --tpm2-device=list
cryptsetup --version                 # >= 2.4
```

**Stop if:**

- root is not partition 2 on `nvme0n1`
- the table is not GPT
- `/boot` has less than 300 MB free

In any of these cases, adjust the commands below first.

## Step 1: backup, and a verified restore

**What to back up:**

- `/home/erikf`, minus `.cache` and other rebuildable caches. Keep every
  agent-trace folder: `~/.claude`, `~/.codex*`, `~/.t3`,
  `~/.local/share/opencode`, `~/agent-traces`.
- `~/.ssh`. sops decrypts with `~/.ssh/id_ed25519`, see `modules/nixos/secrets.nix`.
- `/etc/ssh`, `/etc/NetworkManager/system-connections` and `/var/lib`.
- **Leave out `/nix`.** The cache rebuilds it.

**Target:** the PC, `~/backups/framework-2026-11/`. The PC has 711 GB free on
`/` (2026-11-12); after the backup its `/` stays above the 20 % free alert line.

```sh
# on the framework, as root, over the tailnet to the PC
rsync -aHAX --numeric-ids --info=progress2 \
  --exclude=/home/erikf/.cache --exclude='/home/erikf/**/node_modules' --exclude='/home/erikf/**/target' \
  /home/erikf /etc/ssh /etc/NetworkManager/system-connections /var/lib \
  erikf@pc:backups/framework-2026-11/
```

**Restore check.** All three must pass before step 2:

1. `rsync -aHAXn --checksum --itemize-changes <same sources> erikf@pc:backups/framework-2026-11/`
   prints nothing. The copy matches byte for byte.
2. On the PC, copy a sample out again (`~/obsidian`, `~/.ssh`, one project) to
   a scratch folder and `diff -r` it against the framework.
3. Prove the backed-up key works: on the PC,
   `SOPS_AGE_SSH_PRIVATE_KEY_FILE=~/backups/framework-2026-11/erikf/.ssh/id_ed25519 sops -d hosts/framework/secrets/secrets.yaml >/dev/null`
   succeeds.

## Step 2: encrypt in place (Erik at the laptop, AC power)

1. On the running laptop, stage the LUKS config so the next boot expects it:
   `git -C ~/.dotfiles fetch && git worktree add ~/fw-luks origin/framework-luks-secureboot~1`,
   then `cd ~/fw-luks && rebuild boot`. The previous generation stays in the
   systemd-boot menu. It boots the unencrypted disk, which is the way back if
   step 2 is abandoned before it runs. Until the encryption is done, an
   ordinary reboot must pick that previous entry: the staged one waits for a
   `framework-luks` partition that doesn't exist yet. Rebase the branch onto
   `main` first if `main` has moved on; `rebuild` refuses a checkout that
   lacks the last deployed commit.
2. **Turn off the 06:00 auto-update until step 4 is merged.** It would make the
   non-LUKS `main` the default boot entry again:
   `systemctl --user disable --now auto-update.timer`.
3. Boot a NixOS installer USB (the minimal ISO has cryptsetup), or PXE from the
   PC as with samsung-ablo. Then:

```sh
P=/dev/nvme0n1p2                                  # as confirmed in step 0
e2fsck -f "$P"
resize2fs "$P" $(( ($(blockdev --getsize64 "$P") - 32*1024*1024) / 4096 ))   # 4 KiB blocks
cryptsetup reencrypt --encrypt --type luks2 --reduce-device-size 32M "$P"  # sets the passphrase
sgdisk -c 2:framework-luks /dev/nvme0n1 && udevadm settle
cryptsetup open /dev/disk/by-partlabel/framework-luks cryptroot
e2fsck -f /dev/mapper/cryptroot && resize2fs /dev/mapper/cryptroot
cryptsetup luksHeaderBackup /dev/disk/by-partlabel/framework-luks \
  --header-backup-file /tmp/framework-luks-header.img   # copy it to the PC backup folder
reboot
```

If it's interrupted: boot the USB again and run
`cryptsetup reencrypt --resume-only "$P"`. If it fails outright: restore from
step 1 (option B).

## Step 3: first encrypted boot

- systemd-boot starts the staged generation, and the initrd asks for the
  passphrase.
- Check: `lsblk -f` shows `crypto_LUKS` → `cryptroot` → ext4 on `/`, and
  `cryptsetup status cryptroot` reports it is active.
- Add a recovery key and store it in 1Password, never in the repo:
  `sudo systemd-cryptenroll --recovery-key /dev/disk/by-partlabel/framework-luks`.

## Step 4: put LUKS on main

- Merge commit 1 of the branch into `main` and push.
- Rebuild from `main`.
- Turn the auto-update timer back on.

## Step 5: Secure Boot (lanzaboote, our own keys)

1. `sudo sbctl create-keys`. Keys go to `/var/lib/sbctl`; back that folder up to the PC.
2. Deploy branch commit 2 (`rebuild boot`), then run `sudo sbctl verify`:
   everything in the ESP must be signed. With 5 generations at about 70 MB
   each, the 536 MB ESP is enough.
3. **In the BIOS:** Security → Secure Boot → erase all Secure Boot settings. This
   puts the firmware in setup mode. Set a BIOS supervisor password too, so
   Secure Boot can't simply be switched off.
4. Booted again: `sudo sbctl enroll-keys --microsoft`. Keeping Microsoft's keys
   keeps firmware/option-ROM and fwupd capsule paths working.
5. Turn Secure Boot on in the BIOS. Check: `bootctl status` →
   `Secure Boot: enabled (user)`.
6. If it won't boot: turn Secure Boot off in the BIOS. The disk is unaffected.

## Step 6: TPM unlock

1. Enrol the TPM:
   `sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/disk/by-partlabel/framework-luks`.
   Keep the passphrase and the recovery key.
2. Reboot. It should unlock with no prompt and stop at hyprlock.
3. Firmware or dbx updates change PCR 7. The passphrase prompt then comes back.
   Re-enrol with `--wipe-slot=tpm2 --tpm2-device=auto --tpm2-pcrs=7`.
4. Optional, stronger: `--tpm2-with-pin=yes`. A stolen laptop then can't reach
   the login screen without the PIN, at the cost of unattended reboots.

## What only Erik can do

- Steps 2 and 3, at the laptop:
  - booting from USB
  - choosing the LUKS passphrase
  - typing it on the first boot
- Step 5, BIOS changes:
  - setup mode
  - supervisor password
  - turning Secure Boot on
- Enrolling a finger (`fprintd-enroll`).
- Setting a real login password if it's still the initial one from `main-user.nix`.

## What an agent can do once `ssh framework` answers

- verify the `0ae53b2f` activation
- step 0
- the step 1 backup and its restore checks
- steps 4 and 6 (the TPM enrolment and the checks)
