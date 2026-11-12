# Framework: disk encryption and Secure Boot plan

Erik asked (2026-11-12) for the same endpoint protection on the Framework as on
samsung-ablo. Screen lock, fingerprint and ClamAV are in `main` (`0ae53b2f`).
This file covers the rest: encrypting the root disk, Secure Boot and TPM
unlock. **Nothing here has been run yet**, and step 0 has to be validated on
the live machine before anything else.

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
unlock and lock the screen on this hardware has not been tested. If `main`
moves before step 2, rebase the branch, rebuild it with `nix-remote build`,
and use the new output paths below.

## What is known about the machine

Source: the homelab Prometheus (Alloy node metrics). The last sample is from
**2026-11-11 18:59 CET**; the laptop has been offline since. Nothing below
is trusted until step 0 has checked it again on the machine itself.

| | Last known value |
|---|---|
| Model | Framework Laptop 13 (AMD Ryzen 7040), BIOS 03.20 |
| Disk | PNY CS2140 500 GB NVMe (`nvme0n1`) |
| ESP | vfat `/boot`, UUID `9FF5-7734`, 536 MB, 334 MB free |
| Root | ext4 `/`, UUID `26b10d70-1758-43e3-bde9-c81069b159df`, 459 GB, 111 GB free (~348 GB used, `/nix/store` included) |
| Swap | No disk swap; zram only (RAM, nothing written to disk) |
| RAM | 16 GB |
| NixOS | 26.11.20261107 (before `0ae53b2f`) |

**Not known from here:**

- the partition table type
- the partition numbers
- the ext4 block size
- the TPM 2.0 state
- the current Secure Boot state
- where agent traces live outside the usual folders

The commands below find the partitions by filesystem UUID and read the block
size from the filesystem itself. Nothing is hard-coded.

## Options for encrypting the existing root

| Option | How | Verdict |
|---|---|---|
| **A. In place, offline** | From the installer: shrink the ext4 by 32 MiB, then `cryptsetup reencrypt --encrypt --reduce-device-size 32M`. This is LUKS2 encryption with a data shift; the data stays where it is and the header goes at the start of the partition. | **Recommended.** Supported by cryptsetup (man `cryptsetup-reencrypt`, "encryption with data shift"). No repartitioning or reinstall. The job is resilient: an interrupted run can be resumed with `cryptsetup reencrypt --resume-only`. It runs over the whole partition, so plan for about an hour on AC power. |
| A'. In place, online | Encrypting the mounted, running root | Not possible. cryptsetup can only re-encrypt a device that is already LUKS while it's online; a plain mounted ext4 can't be switched over. |
| B. Fresh LUKS + full restore | New LUKS2 + ext4 on the same partition, then the step 2 root archive extracted and the LUKS system installed | **Fallback**, exact commands in section R. Also usable instead of A. |
| C. Encrypt only `/home` | fscrypt, or a separate LUKS volume | Rejected. `/etc/ssh`, `/var/lib`, Wi-Fi keys and logs would stay in clear text. |

Swap needs nothing: there is no disk swap, and zram lives in RAM. Hibernation
stays unavailable. If disk swap is ever added, put it inside `cryptroot`, as a
swapfile.

## Backup protection and keys

The PC's disk is **not** encrypted (Erik's choice), so nothing secret goes
there in plain text.

- **Storage:** everything lives in `~/backups/framework-2026-11/` on the PC
  (directory 0700, files 0600). That path is outside every Syncthing folder
  (obsidian, Camera, sync, wallpapers) and outside the agent cleanup paths.
- **Encryption:** every archive is streamed through `zstd` and `age` on the PC.
  It goes to **two recipients**, listed in `recipients.txt` in that folder:
  1. The PC's `~/.ssh/id_ed25519.pub` (`SHA256:5s/kBwyrgmb4E4pNzm/lZzZAwQQ4ZlBko11c7xWAweI`).
     This is the same key as the sops `primary` age key
     (`age1jygscgy2…`), checked with `ssh-to-age` on 2026-11-12.
  2. A dedicated recovery key from `age-keygen`. Its private half goes **into
     1Password** (secure note "Framework backup 2026-11 age key") and is then
     deleted from disk. With it, the backups survive losing the PC as well.
     Creating it needs 1Password signed in; if that isn't possible, print the
     key on paper instead. One of the two has to happen before step 2.
- **What it covers:** the root archive, the ESP archive, the `/tmp` archive,
  the LUKS header backup and the sbctl keys. All are encrypted this way.
- **Kept outside the PC's disk:** the LUKS passphrase and the LUKS recovery key
  (1Password).
- **Retention:** keep the backups until the encrypted system has run for 30
  days. Only Erik deletes them.

`TARC` below is the same tar flag set everywhere:
`--numeric-owner --acls --xattrs --xattrs-include='*'`. It keeps root/uid
ownership, modes, ACLs, xattrs and the original hierarchy inside the archive.
Nothing is ever unpacked as `erikf` on the PC. This pipeline (create, compare,
detect a change, extract with xattrs) was tested on a scratch tree on
2026-11-12 with GNU tar 1.35, zstd and age.

## Step 0: checks on the running laptop (agent, over `ssh framework`)

```sh
ssh framework 'sudo -n true && echo sudo-ok'          # the agent steps need passwordless sudo
ssh framework 'lsblk -o NAME,SIZE,TYPE,FSTYPE,PARTLABEL,UUID,MOUNTPOINTS; findmnt -no SOURCE,FSTYPE / /boot /tmp /var/tmp'
ssh framework 'R=$(blkid -U 26b10d70-1758-43e3-bde9-c81069b159df); D=/dev/$(lsblk -no PKNAME $R); sudo sgdisk -p $D; sudo dumpe2fs -h $R | grep -E "^(Block size|Block count|Filesystem features)"'
ssh framework 'bootctl status | grep -iE "secure boot|tpm|setup mode"; systemd-cryptenroll --tpm2-device=list'
ssh framework 'sudo du -sx --exclude=/nix/store -B1 / | cut -f1'   # bytes the root archive will hold, before compression
df -B1 --output=avail ~                                           # on the PC
```

**Stop if:**

- sudo needs a password
- the table is not GPT
- `/` is not ext4 on `26b10d70-…`
- the archive estimate is larger than the PC's free space minus 370 GB (keeps
  the PC's `/` above its 20 % free alert)

## Step 1: preparation on the running laptop

### 1a. Agent traces: inventory and preserve (agent)

Erik's rule is that agent traces are never deleted. The root archive (step 2)
contains **every file on the root filesystem except `/nix/store`**. Nothing
under `/home` is excluded, so caches, `target/` and `node_modules` are all
kept. `/nix/store` is left out because only the Nix daemon writes there and
every path in it can be fetched again from the cache or rebuilt from the flake.
The inventory below records where traces are, so step 2 can prove each one is
in the archive.

```sh
B=~/backups/framework-2026-11; install -d -m 0700 "$B"
ssh framework 'for d in ~/.claude ~/.claude_2 ~/.codex ~/.codex-t3 ~/.codex-* ~/.t3/userdata ~/.local/share/opencode ~/.grok ~/.omp ~/agent-traces; do [ -e "$d" ] && du -sxh "$d"; done' > "$B/trace-dirs.txt"
ssh framework 'sudo -n find / -xdev -path /nix/store -prune -o -type f \( -name "*.jsonl" -o -name "*transcript*" -o -path "*/.claude/projects/*" -o -path "*/.codex*/sessions/*" \) -print' \
  | sed 's|^/|./|' | sort > "$B/trace-files.txt"
wc -l "$B/trace-files.txt"
```

`/tmp`, `/var/tmp` and `/run/user/1000` are wiped on every reboot if step 0
showed them as tmpfs, so their contents are archived now, unfiltered. That
includes agent task outputs such as `/tmp/claude-1000/`.

```sh
ssh framework "sudo -n tar --create --file=- --directory=/ --numeric-owner --acls --xattrs --xattrs-include='*' --ignore-failed-read tmp var/tmp run/user/1000" \
  | zstd -T0 -q | age -R "$B/recipients.txt" > "$B/tmpfs.tar.zst.age"
age -d -i ~/.ssh/id_ed25519 "$B/tmpfs.tar.zst.age" | zstd -dq | tar --list --file=- | wc -l   # > 0
```

This archive is a snapshot of directories that are still changing, so it is
checked by listing, not with `--compare`.

### 1b. Recovery key (Erik + agent)

```sh
umask 077
age-keygen -o "$XDG_RUNTIME_DIR/fw-backup.key"          # tmpfs, never on disk
{ cat ~/.ssh/id_ed25519.pub; age-keygen -y "$XDG_RUNTIME_DIR/fw-backup.key"; } > "$B/recipients.txt"
echo canary | age -R "$B/recipients.txt" > "$B/canary.age"
age -d -i "$XDG_RUNTIME_DIR/fw-backup.key" "$B/canary.age"   # prints canary: the recovery key decrypts
age -d -i ~/.ssh/id_ed25519 "$B/canary.age"                  # prints canary: the PC key decrypts
# Erik stores the key file's contents in 1Password, then:
shred -u "$XDG_RUNTIME_DIR/fw-backup.key"
```

Do 1b before 1a's `/tmp` archive, which needs `recipients.txt`.

### 1c. Stage the config (agent)

1. On the running laptop: `git -C ~/.dotfiles fetch origin framework-luks-secureboot`
   and `git -C ~/.dotfiles worktree add ~/fw-luks <commit-1 sha>`, then
   `cd ~/fw-luks && rebuild boot`. The previous generation stays in the
   systemd-boot menu and boots the unencrypted disk.
   - **Until the encryption is done, every reboot must pick that previous
     entry.** The staged one waits for a `framework-luks` partition that
     doesn't exist yet.
   - `rebuild` refuses a checkout that lacks the last deployed commit, so
     rebase onto `main` first if needed.
2. **Turn off the 06:00 auto-update until step 4 is merged.** It would make the
   non-LUKS `main` the default boot entry again:
   `systemctl --user disable --now auto-update.timer`.
3. Build the installer: `nix build --no-link --print-out-paths .#samsung-ablo-installer-img`.
   It's a generic x86_64 NixOS installer with the newest kernel and
   NetworkManager, and root accepts the PC's SSH key, so nobody types a
   password. Write it to a stick (`hosts/samsung-ablo/README.md`), or PXE-boot
   the netboot variant from the PC.

## Step 2: installer session (Erik boots it; the agent drives from the PC)

Erik boots the stick on AC power. For network he plugs in Ethernet or runs
`nmtui`, then reads the address off the console. Everything else runs from
the PC with `F=root@<address>` and `set -euo pipefail`.

### 2a. Validate the live, unmounted layout (read only)

```sh
ssh $F 'set -e
P=$(blkid -U 26b10d70-1758-43e3-bde9-c81069b159df); ESP=$(blkid -U 9FF5-7734)
DISK=/dev/$(lsblk -no PKNAME "$P"); PARTN=$(cat /sys/class/block/${P#/dev/}/partition)
BS=$(dumpe2fs -h "$P" 2>/dev/null | sed -n "s/^Block size: *//p")
BC=$(dumpe2fs -h "$P" 2>/dev/null | sed -n "s/^Block count: *//p")
DEV=$(blockdev --getsize64 "$P")
printf "P=%s\nESP=%s\nDISK=%s\nPARTN=%s\nBS=%s\nBC=%s\nDEV=%s\n" "$P" "$ESP" "$DISK" "$PARTN" "$BS" "$BC" "$DEV" | tee /root/fw.env
sgdisk -p "$DISK"; lsblk -o NAME,SIZE,FSTYPE,UUID,PARTLABEL,MOUNTPOINTS "$DISK"
for t in cryptsetup e2fsck resize2fs dumpe2fs sgdisk tar blkid; do command -v $t >/dev/null || echo "MISSING $t"; done
cryptsetup --version; tar --help | grep -q -- --xattrs-include || echo "tar lacks xattrs"
findmnt -S "$P" && echo "ROOT IS MOUNTED"; findmnt -S "$ESP" && echo "ESP IS MOUNTED"; true' | tee "$B/layout.txt"
```

**Gate (all must hold):**

- `P` and `ESP` were found.
- `sgdisk` reports GPT.
- `BS` is 1024, 2048 or 4096.
- `BS*BC <= DEV`.
- Nothing is reported missing or mounted.
- cryptsetup is 2.4 or newer.

`layout.txt` on the PC keeps these values. If the installer reboots, recreate
`/root/fw.env` from it.

### 2b. Backup (root mounted read-only, so the copy is consistent)

```sh
TARC="--numeric-owner --acls --xattrs --xattrs-include='*'"
ssh $F '. /root/fw.env; mkdir -p /mnt/root /mnt/esp; mount -o ro "$P" /mnt/root; mount -o ro "$ESP" /mnt/esp'
ssh $F "tar --create --file=- --directory=/mnt/root --sparse $TARC --exclude=./nix/store ." \
  | zstd -T0 -q | age -R "$B/recipients.txt" > "$B/root.tar.zst.age"
ssh $F "tar --create --file=- --directory=/mnt/esp $TARC ." \
  | zstd -T0 -q | age -R "$B/recipients.txt" > "$B/esp.tar.zst.age"
chmod 0600 "$B"/*; (cd "$B" && sha256sum *.age > SHA256SUMS)
```

The root goes over the network once. Over Wi-Fi that can take one to two
hours; Ethernet is faster.

### 2c. Restore checks (all must pass before 2d)

```sh
dec() { age -d -i ~/.ssh/id_ed25519 "$B/$1" | zstd -dq; }
(cd "$B" && sha256sum -c SHA256SUMS)
# 1. Byte-for-byte restore dry run against the read-only disk: no output, exit 0.
dec root.tar.zst.age | ssh $F "tar --compare --file=- --directory=/mnt/root $TARC"
dec esp.tar.zst.age  | ssh $F "tar --compare --file=- --directory=/mnt/esp $TARC"
# 2. Nothing missing: every path on the disk except ./nix/store is in the archive.
ssh $F 'cd /mnt/root && find . -path ./nix/store -prune -o -print' | sort > "$B/disk.list"
dec root.tar.zst.age | tar --list --file=- | sed 's|/$||' | sort > "$B/archive.list"
comm -23 "$B/disk.list" "$B/archive.list"                     # must print nothing
comm -23 "$B/trace-files.txt" "$B/archive.list"               # traces from 1a, must print nothing
# 3. The sops key inside the archive decrypts the Framework's secrets.
K="$XDG_RUNTIME_DIR/fw-id"; umask 077
dec root.tar.zst.age | tar --extract --file=- --to-stdout ./home/erikf/.ssh/id_ed25519 > "$K"
env -u SOPS_AGE_KEY_FILE HOME=/nonexistent SOPS_AGE_KEY="$(nix shell nixpkgs#ssh-to-age -c ssh-to-age -private-key -i "$K")" \
  sops -d ~/.dotfiles/hosts/framework/secrets/secrets.yaml >/dev/null && echo sops-ok   # HOME override: the PC's own key must not be the one that works
shred -u "$K"
```

`trace-files.txt` was taken while the system was running. A file that was
deleted before shutdown shows up in the second `comm`. Check each such line
against the 1a `/tmp` archive or the shutdown, rather than ignoring it.

### 2d. Shrink the filesystem (first disk write; uses the measured block size)

```sh
ssh $F 'set -e; . /root/fw.env; umount /mnt/root /mnt/esp
findmnt -S "$P" && exit 1
e2fsck -f -p "$P" || [ $? -le 1 ]          # 0 clean, 1 fixed; anything else stops
NEW=$(( (DEV - 32*1024*1024) / BS ))            # in filesystem blocks of size BS
MIN=$(resize2fs -P "$P" 2>/dev/null | sed -n "s/.*: *//p")
[ "$NEW" -gt "$MIN" ] || { echo "too full to shrink"; exit 1; }
resize2fs "$P" "$NEW"
BC2=$(dumpe2fs -h "$P" 2>/dev/null | sed -n "s/^Block count: *//p")
[ $(( BC2 * BS )) -le $(( DEV - 32*1024*1024 )) ] && echo shrink-ok'
```

### 2e. Encrypt in place (Erik types the passphrase on the laptop)

Erik runs this on the laptop's console, because cryptsetup asks for the new
passphrase twice:

```sh
. /root/fw.env
cryptsetup reencrypt --encrypt --type luks2 --reduce-device-size 32M "$P"
sgdisk -c "$PARTN:framework-luks" "$DISK" && udevadm settle
cryptsetup open /dev/disk/by-partlabel/framework-luks cryptroot
e2fsck -f /dev/mapper/cryptroot && resize2fs /dev/mapper/cryptroot
cryptsetup luksHeaderBackup /dev/disk/by-partlabel/framework-luks --header-backup-file /root/luks-header.img
```

The agent then stores the header encrypted and removes the copy from the
installer's RAM, before the reboot:

```sh
ssh $F 'cat /root/luks-header.img' | age -R "$B/recipients.txt" > "$B/luks-header.img.age"
ssh $F 'shred -u /root/luks-header.img; cryptsetup close cryptroot; reboot'
```

## Section R: when step 2e fails

| Situation | What to do |
|---|---|
| Interrupted: power, crash or Ctrl-C | Boot the installer again, recreate `/root/fw.env` from `layout.txt`, then run `cryptsetup reencrypt --resume-only "$P"` and continue 2e from `sgdisk`. |
| LUKS header damaged, data intact | `age -d -i ~/.ssh/id_ed25519 "$B/luks-header.img.age" \| ssh $F 'cat > /root/h.img'`, then `cryptsetup luksHeaderRestore "$P" --header-backup-file /root/h.img`. This only works if 2e got as far as the header backup. |
| Not resumable, or the data is unreadable | Full restore (below). |

**Full restore** (option B). It writes over the partition, so only do it after
the situation above is clear. Use the same installer session and the
`/root/fw.env` values.

```sh
# Erik, on the laptop console (passphrase prompt):
. /root/fw.env
wipefs -a "$P"
cryptsetup luksFormat --type luks2 "$P"
sgdisk -c "$PARTN:framework-luks" "$DISK" && udevadm settle
cryptsetup open /dev/disk/by-partlabel/framework-luks cryptroot

# Agent, from the PC:
ssh $F '. /root/fw.env; mkfs.ext4 -b "$BS" -U 26b10d70-1758-43e3-bde9-c81069b159df /dev/mapper/cryptroot
mkdir -p /mnt/root && mount /dev/mapper/cryptroot /mnt/root'
age -d -i ~/.ssh/id_ed25519 "$B/root.tar.zst.age" | zstd -dq \
  | ssh $F "tar --extract --file=- --directory=/mnt/root $TARC --same-permissions --same-owner"
age -d -i ~/.ssh/id_ed25519 "$B/root.tar.zst.age" | zstd -dq \
  | ssh $F "tar --compare --file=- --directory=/mnt/root $TARC"      # must be silent
# The ESP is never written by this plan. Only if it is damaged:
#   ssh $F '. /root/fw.env; mkfs.vfat -F 32 -i 9FF57734 "$ESP"'
#   then extract esp.tar.zst.age into it the same way.
ssh $F '. /root/fw.env; mkdir -p /mnt/root/boot && mount "$ESP" /mnt/root/boot
nixos-install --root /mnt/root --no-root-passwd --no-channel-copy \
  --system /nix/store/vm72sdq7llqwx3ckjl9kh244cifbpxhk-nixos-system-framework-26.11.20261107.f4a03c0'
```

- The `--system` path is the LUKS build (branch commit 1). It comes from the
  homelab cache, which the installer already uses. If the branch was rebuilt,
  use the new path.
- `nixos-install` refills `/nix/store` (left out of the archive) and writes
  the boot entries.
- After the reboot, continue with step 3.
- If the laptop has to go back unencrypted instead: same steps, but skip
  `luksFormat`/`open` and use `mkfs.ext4` on `$P` directly, with
  `--system /nix/store/xbvq7rlw…` (main, `0ae53b2f`).

## Step 3: first encrypted boot

- systemd-boot starts the staged generation, and the initrd asks for the
  passphrase.
- Check: `lsblk -f` shows `crypto_LUKS` → `cryptroot` → ext4 on `/`, and
  `cryptsetup status cryptroot` reports it is active.
- Add a recovery key and store it in 1Password, never in the repo or on the PC:
  `sudo systemd-cryptenroll --recovery-key /dev/disk/by-partlabel/framework-luks`.

## Step 4: put LUKS on main

- Merge commit 1 of the branch into `main` and push.
- Rebuild from `main`.
- Turn the auto-update timer back on.

## Step 5: Secure Boot (lanzaboote, our own keys)

1. `sudo sbctl create-keys`. Keys go to `/var/lib/sbctl`. Back them up
   encrypted, from the PC:
   `ssh framework 'sudo -n tar --create --file=- --directory=/var/lib sbctl' | age -R "$B/recipients.txt" > "$B/sbctl.tar.age"`.
2. Deploy branch commit 2 (`rebuild boot`), then run `sudo sbctl verify`:
   everything in the ESP must be signed. With 5 generations at about 70 MB
   each, the 536 MB ESP is enough.
3. **In the BIOS:**
   - Security → Secure Boot → erase all Secure Boot settings. This puts the
     firmware in setup mode.
   - Set a BIOS supervisor password too, so Secure Boot can't simply be
     switched off.
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

## Who does what

**Erik:**

- Turn the Framework on, at home and on AC, so `ssh framework` answers. This
  is the current blocker.
- Store the recovery key in 1Password (1b).
- Boot the installer (2) and choose and type the LUKS passphrase (2e, R).
- Type the passphrase on the first boot (3).
- BIOS changes (5): setup mode, supervisor password, Secure Boot on.
- `fprintd-enroll`, and `passwd` if the login password is still the initial
  one from `main-user.nix`.

**Agent, once `ssh framework` answers:**

- verify the `0ae53b2f` activation
- step 0 and its gates
- 1a and 1c
- 2a–2d and the restore checks
- the header backup
- R, apart from the passphrase
- steps 4, 5.1–5.2 and 6

## Checks done on the PC for this plan (2026-11-12, nothing on the Framework)

- The tar create → compare → change detected → extract pipeline, with ACLs
  and xattrs, through zstd and age to the PC's SSH key: tested on a scratch
  tree.
- sops 3.13.3 does not read `SOPS_AGE_SSH_PRIVATE_KEY_FILE`. The
  `ssh-to-age -private-key` + `SOPS_AGE_KEY` form in 2c decrypts
  `hosts/framework/secrets/secrets.yaml` with the key from the PC. With
  `HOME` pointing elsewhere and no key given, sops fails, so the check does
  test the restored key.
- The PC's SSH key is the sops `primary` age key.
- Not tested anywhere: the Framework's own layout, block size, sudo, `tar`,
  `cryptsetup` and `resize2fs` on that disk, and the installer image on that
  hardware. Steps 0 and 2a are the gates for these.
