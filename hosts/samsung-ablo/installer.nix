# USB installer for the samsung-ablo laptop: the stock NixOS minimal ISO plus what
# lets an agent on the pc take over the moment it is on the network.
#
#   nix build --no-link --print-out-paths .#samsung-ablo-installer-iso
#
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
  imports = [ (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix") ];

  networking.hostName = "samsung-ablo-installer";

  boot.kernelPackages = pkgs.linuxPackages_latest;
  # ZFS often lags the newest kernel and nothing here needs it.
  boot.supportedFilesystems.zfs = lib.mkForce false;

  # The minimal ISO uses wpa_supplicant; NetworkManager gives nmtui.
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

  # Faster to build than the default xz, and the stick is big enough.
  isoImage.squashfsCompression = "zstd -Xcompression-level 6";
}
