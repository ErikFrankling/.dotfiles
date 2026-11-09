# USB installer for the samsung-ablo laptop: the stock NixOS installer
# profile, written as a plain GPT disk (FAT32 EFI partition + ext4 root,
# systemd-boot) instead of an ISO. The Galaxy Book6's firmware (AMI, 2026)
# does not list a dd-written NixOS ISO at all: its hybrid MBR puts the EFI
# partition inside the CD image. A normal GPT stick it boots.
#
#   nix build --no-link --print-out-paths .#samsung-ablo-installer-img
#   sudo dd if=<result>/*.img of=/dev/sdX bs=4M oflag=direct conv=fsync
#
# On top of the stock installer:
# - root accepts the pc's SSH key, so nobody types a password;
# - the newest kernel, so a 2026 laptop's NVMe, Wi-Fi and graphics work;
# - NetworkManager, so Wi-Fi is one `nmtui` away (Ethernet just works);
# - Erik's binary caches, so nixos-anywhere fetches the system from them
#   instead of copying it all from the pc.
{
  lib,
  pkgs,
  modulesPath,
  ...
}:
{
  imports = [
    (modulesPath + "/profiles/base.nix")
    (modulesPath + "/profiles/installation-device.nix")
    (modulesPath + "/profiles/minimal.nix")
  ];

  hardware.enableAllHardware = true;
  # A stick moves between machines: never write EFI variables, boot through
  # the removable-media path.
  boot.loader.efi.canTouchEfiVariables = false;

  networking.hostName = "samsung-ablo-installer";

  boot.kernelPackages = pkgs.linuxPackages_latest;
  # ZFS often lags the newest kernel and nothing here needs it.
  boot.supportedFilesystems.zfs = lib.mkForce false;

  networking.wireless.enable = lib.mkForce false;
  networking.networkmanager.enable = true;

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJXhLc3vVBQPQLGlf4kMJ/WHXPlsXWzuustUwzFj/AaX erikf@arch-erik-pc"
  ];

  # Show the address on the console, in case the pc cannot find it.
  services.getty.helpLine = lib.mkAfter ''

    samsung-ablo installer. Network: plug in Ethernet, or run `nmtui` for Wi-Fi.
    Addresses: \4
  '';

  environment.systemPackages = with pkgs; [
    sbctl
    git
  ];

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    substituters = [
      "https://nix-cache.erikfrankling.duckdns.org"
      "https://install.determinate.systems"
      "https://cache.numtide.com"
      "https://nix-community.cachix.org"
    ];
    trusted-public-keys = [
      "nix-cache.erikfrankling.duckdns.org-1:i1VytpUS/NiHyPJq8tWmvhrhfBL7L3+ZOcVYq2BXWdA="
      "cache.flakehub.com-3:hJuILl5sVK4iKm86JzgdXW12Y2Hwd5G07qKtHTOcDCM="
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  system.stateVersion = "26.05";
}
