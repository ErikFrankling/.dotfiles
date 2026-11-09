# samsung-ablo: work laptop

Samsung Galaxy Book6 Pro 14 (Intel Core Ultra 7 356H, Panther Lake), Erik's
laptop for Ablo. Dual boot: Windows 11 (BitLocker, ~200 GB, kept for testing
Windows apps) and NixOS on a LUKS2 partition, set up like `framework`, plus the
SOC 2 endpoint controls. Hardware and BIOS research:
`~/projects/ablo/research/samsung-galaxy-book6-linux-2026-11-09.md`; Vanta and
SOC 2 research: `~/projects/ablo/research/`.

| File | What |
|---|---|
| `configuration.nix`, `home.nix` | The host, copied from framework minus Framework-only hardware |
| `hardware-configuration.nix` | Generated on the laptop, plus the LUKS device `cryptroot` and the shared EFI partition |
| `soc2.nix` | SOC 2 controls: disk encryption check, screen lock, ClamAV, 1Password, firewall |
| `vanta.nix` | Vanta Device Monitor from the official .deb, run through nix-ld |
| `installer.nix` | The installer: root SSH with the pc's key, newest kernel, NetworkManager |
| `disko.nix` | Unused whole-disk layout (would wipe Windows) |
| `secrets/secrets.yaml` | sops: Tailscale OAuth key, Syncthing identity, OpenCode/Executor keys, later `vanta-key` |

## The BIOS (PRHK.1.4.56.576, 2026)

F2 opens setup: tiles SysInfo / Advanced / Security / Boot. **Boot** has
Secure Boot Control, Secure Boot Certificate keyset ("Microsoft Windows
only"), USB LAN PXE OPROM, Boot Menu, USB Booting and Boot Device Priority.
There is no Fast BIOS Mode. **USB sticks and network boot only appear in the
F10/F12 boot menu at power-on**, never in Boot Device Priority. Windows Hello's
PIN fails while Secure Boot is off (TPM measurements change).

## Install, step by step

**Erik** does the steps that need hands at the laptop. **Agent** means a
session on the pc.

1. **Erik**, in Windows (Secure Boot on, so the PIN works): note the BitLocker
   recovery key (`manage-bde -protectors -get C:`), then Disk Management >
   C: > Shrink Volume to ~200 GB. Leave the rest unallocated.
2. **Erik**: F2 > Boot > Secure Boot Control **Off** > Save. Power off.
3. **Agent**: start the installer, either way:
   - Network (what worked): build the netboot files from `installer.nix` plus
     `<nixpkgs>/nixos/modules/installer/netboot/netboot-minimal.nix`, open
     UDP 67/69/4011 and TCP 64172 (`nixos-firewall-tool open`), run
     `sudo pixiecore boot <kernel> <initrd> --cmdline "init=<toplevel>/init
     loglevel=4" --dhcp-no-bind --port 64172 --status-port 64172`.
     **Erik**: Ethernet in, power on, F10, the IPv4 network entry.
   - USB: `nix build .#samsung-ablo-installer-img`, `dd` it to a stick,
     `sgdisk -e`. **Erik**: stick in before power-on, F10, the stick.
4. **Agent**, over SSH as root on the installer (`hostname` =
   `samsung-ablo-installer`), in the free space after Windows:

   ```sh
   sgdisk -n 5:0:0 -t 5:8309 -c 5:samsung-ablo-luks /dev/nvme0n1   # largest free block
   cryptsetup luksFormat --type luks2 --key-file /tmp/disk.key /dev/nvme0n1p5
   cryptsetup open --key-file /tmp/disk.key /dev/nvme0n1p5 cryptroot
   mkfs.ext4 -L nixos /dev/mapper/cryptroot
   mount /dev/mapper/cryptroot /mnt
   mount -o umask=0077 /dev/nvme0n1p1 /mnt/boot   # Windows' EFI partition
   ```

   `hardware-configuration.nix` finds them by that partition name and the
   EFI partition's UUID. Then
   from the pc:

   ```sh
   nixos-anywhere --flake .#samsung-ablo --target-host root@<ip> \
     --phases install,reboot \
     --extra-files <dir> --chown /home/erikf 1000:100
   ```

   `<dir>` holds `/var/lib/sbctl` (Secure Boot keys made with
   `sbctl --disable-landlock create-keys`), `/etc/ssh/ssh_host_ed25519_key`
   (pinned in `modules/nixos/default.nix`) and `/home/erikf/.ssh/id_ed25519`
   (sops decrypts with it).

   The install did **not** register a firmware boot entry (only Windows Boot
   Manager was listed). From the installer: `efibootmgr --create --disk
   /dev/nvme0n1 --part 1 --loader '\EFI\systemd\systemd-bootx64.efi' --label
   'Linux Boot Manager'`, then `efibootmgr -o <that>,<Windows>,...`.
5. **Erik**: type the LUKS passphrase at boot. Hyprland starts (autologin
   after the disk passphrase). Run `passwd`: the screen lock checks this
   password, and the initial one is the shared default.

   First boot, 2026-11-09: Syncthing created `~/.config` as root before Home
   Manager ran, so `home-manager-erikf` failed (dconf: permission denied) and
   Hyprland did not start. Fix: `sudo chown erikf:users ~/.config && sudo
   systemctl restart home-manager-erikf getty@tty1`.
6. **Agent** over SSH: clone `~/.dotfiles`, check Tailscale came up (the OAuth
   key in sops joins it as `tag:client`). Reach it with `ssh samsung-ablo`
   (tailnet IP through proxmox). Its LAN IPv4 does not answer the pc once
   Tailscale accepts the home subnet route; IPv6 link-local does. The desk's
   USB Ethernet adapter sits behind the KVM, so the laptop loses it whenever
   the KVM switches to the pc: use Wi-Fi.
7. **Secure Boot** (lanzaboote already signs the boot files). Windows asks for
   the BitLocker recovery key once after this.
   - **Erik**: BIOS > Secure Boot: clear the keys / Setup Mode (not found in
     the Boot tile; maybe Security > Enhanced Security Configuration), boot
     NixOS.
   - **Agent**: `sudo sbctl enroll-keys --microsoft` (keeps Windows and
     firmware option ROMs booting).
   - **Erik**: BIOS > Secure Boot Control **On**, boot. `bootctl status` shows
     `Secure Boot: enabled (user)`.

   If this BIOS has no way to clear the keys, Secure Boot stays off; LUKS
   still covers the disk-encryption control.
8. **Vanta**: put the key from https://app.vanta.com/computers?tab=unmonitored
   into sops (`sops hosts/samsung-ablo/secrets/secrets.yaml`, key `vanta-key`), add
   `sops.secrets.vanta-key = { };` to `vanta.nix`, check `ownerEmail` there,
   rebuild. `sudo /var/vanta/vanta-cli status`.

## SOC 2 evidence

Vanta's agent does not support NixOS, so the controls are shown with manual
evidence (Vanta: Documents > Add document; help.vanta.com 11345596). For each
control capture the device, date and command output:

| Control | Command |
|---|---|
| Disk encryption | `lsblk -f`, `sudo cryptsetup luksDump /dev/nvme0n1p5 \| head` |
| Secure Boot | `bootctl status \| grep -i secure`, `sudo sbctl status` |
| Screen lock | `systemctl --user status hypridle`, `cat ~/.config/hypr/hypridle.conf` (lock after 300 s and before sleep); then a real test: leave it idle 5 min, it locks |
| Anti-malware | `systemctl status clamav-daemon clamav-clamonacc clamav-freshclam`, `sudo freshclam --version`, `systemctl list-timers clamdscan` |
| Password manager | `1password --version`, the app signed in |
| Patching | `journalctl --user -u auto-update -n 20`, `nixos-version` |
| Firewall | `sudo nft list ruleset \| head` |
| Vanta agent | `sudo /var/vanta/vanta-cli status`, `sudo /var/vanta/vanta-cli list encryption` |
