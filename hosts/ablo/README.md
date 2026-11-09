# ablo: work laptop

Samsung Galaxy Book6 Pro 14 (Intel Core Ultra 7 356H, Panther Lake), Erik's
laptop for Ablo. NixOS, set up like `framework`, plus the SOC 2 endpoint
controls. Hardware and BIOS research:
`~/projects/ablo/research/samsung-galaxy-book6-linux-2026-11-09.md`; Vanta and
SOC 2 research: `~/projects/ablo/research/`.

| File | What |
|---|---|
| `configuration.nix`, `home.nix` | The host, copied from framework minus Framework-only hardware |
| `soc2.nix` | SOC 2 controls: disk encryption check, screen lock, ClamAV, 1Password, firewall |
| `vanta.nix` | Vanta Device Monitor from the official .deb, run through nix-ld |
| `disko.nix` | Disk layout: 1 GB EFI + LUKS2 ext4 root |
| `installer.nix` | The USB installer: root SSH with the pc's key, newest kernel, NetworkManager |
| `secrets/secrets.yaml` | sops: Tailscale OAuth key, Syncthing identity, OpenCode/Executor keys, later `vanta-key` |

## Install, step by step

**Erik** does the steps that need hands at the laptop. **Agent** means a
session on the pc.

1. **Agent**: build the installer and write it to a stick.
   `nix build --no-link --print-out-paths .#ablo-installer-iso`, then
   `sudo dd if=<iso> of=/dev/sdX bs=4M oflag=direct conv=fsync`.
2. **Erik**, BIOS (F2 at the Samsung logo, or from Windows Shift+Restart >
   Troubleshoot > Advanced options > UEFI Firmware Settings):
   Secure Boot Control **Off**, Fast BIOS Mode **Off**, any VMD/RST/RAID
   storage mode **off/AHCI**. F10 saves. Then F10 at the logo for the boot
   menu, pick the stick.
3. **Erik**: network. Ethernet just works; for Wi-Fi run `nmtui`. The console
   shows the address.
4. **Agent**: finds the installer on the LAN (port 22, hostname
   `ablo-installer`), saves `nixos-generate-config --no-filesystems
   --show-hardware-config` as `hardware-configuration.nix`, commits, and runs
   from the pc:

   ```sh
   nixos-anywhere --flake .#ablo --target-host root@<ip> \
     --disk-encryption-keys /tmp/disk.key <file with the LUKS passphrase> \
     --extra-files <dir> --chown /home/erikf 1000:100
   ```

   `<dir>` holds `/var/lib/sbctl` (Secure Boot keys made with
   `sbctl --disable-landlock create-keys`), `/etc/ssh/ssh_host_ed25519_key`
   (pinned in `modules/nixos/default.nix`) and `/home/erikf/.ssh/id_ed25519`
   (sops decrypts with it). The disk is wiped. It reboots by itself.
5. **Erik**: type the LUKS passphrase at boot. Hyprland starts (autologin
   after the disk passphrase). Run `passwd`: the screen lock checks this
   password, and the initial one is the shared default.
6. **Agent** over SSH: clone `~/.dotfiles`, check Tailscale came up (the OAuth
   key in sops joins it as `tag:client`), and add the SSH alias.
7. **Secure Boot** (lanzaboote already signs the boot files):
   - **Erik**: BIOS > Secure Boot: clear the keys / Setup Mode (wording varies),
     boot NixOS.
   - **Agent**: `sudo sbctl enroll-keys --microsoft` (keep Microsoft's keys:
     firmware option ROMs are signed with them).
   - **Erik**: BIOS > Secure Boot Control **On**, boot. `bootctl status` shows
     `Secure Boot: enabled (user)`.

   If this BIOS has no way to clear the keys, Secure Boot stays off; LUKS
   still covers the disk-encryption control.
8. **Vanta**: put the key from https://app.vanta.com/computers?tab=unmonitored
   into sops (`sops hosts/ablo/secrets/secrets.yaml`, key `vanta-key`), add
   `sops.secrets.vanta-key = { };` to `vanta.nix`, check `ownerEmail` there,
   rebuild. `sudo /var/vanta/vanta-cli status`.

## SOC 2 evidence

Vanta's agent does not support NixOS, so the controls are shown with manual
evidence (Vanta: Documents > Add document; help.vanta.com 11345596). For each
control capture the device, date and command output:

| Control | Command |
|---|---|
| Disk encryption | `lsblk -f`, `sudo cryptsetup luksDump /dev/nvme0n1p2 \| head` |
| Secure Boot | `bootctl status \| grep -i secure`, `sudo sbctl status` |
| Screen lock | `systemctl --user status hypridle`, `cat ~/.config/hypr/hypridle.conf` (lock after 300 s and before sleep); then a real test: leave it idle 5 min, it locks |
| Anti-malware | `systemctl status clamav-daemon clamav-clamonacc clamav-freshclam`, `sudo freshclam --version`, `systemctl list-timers clamdscan` |
| Password manager | `1password --version`, the app signed in |
| Patching | `journalctl --user -u auto-update -n 20`, `nixos-version` |
| Firewall | `sudo nft list ruleset \| head` |
| Vanta agent | `sudo /var/vanta/vanta-cli status`, `sudo /var/vanta/vanta-cli list encryption` |
