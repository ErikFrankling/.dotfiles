# samsung-ablo: Erik's work laptop (Samsung Galaxy Book6 Pro 14, Intel Core Ultra 7
# 356H "Panther Lake"). Set up like the framework, plus the SOC 2 controls in
# soc2.nix. Install and first-boot steps: README.md in this folder.
{
  config,
  pkgs,
  lib,
  inputs,
  hostName,
  username,
  otherPkgs,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    # Dual boot instead (Erik, 2026-11-09: keep Windows, ~200 GB, for testing
    # Windows apps). The LUKS partition and file systems are in
    # hardware-configuration.nix; README.md has the partitioning commands.
    # inputs.disko.nixosModules.disko
    # ./disko.nix # whole-disk layout that would wipe Windows
    ./soc2.nix
    ../../modules/nixos
    ../../modules/nixos/secure-boot.nix
    ../../modules/nixos/tailscale.nix
    ../../modules/nixos/laptop.nix
    ../../modules/nixos/auto-update.nix
    ../../modules/nixos/desktop.nix
    # ../../modules/nixos/game.nix # work laptop: no Steam
    inputs.home-manager.nixosModules.default
    ../../modules/nixos/vm-host.nix
    inputs.batmon.nixosModules.default
  ];

  networking.hostName = "samsung-ablo";

  # Panther Lake (Xe3 graphics, BE211 Wi-Fi, SoundWire audio) wants a new
  # kernel; the LTS one is too old for parts of it.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Secure Boot through lanzaboote (modules/nixos/secure-boot.nix); keys are
  # in /var/lib/sbctl, enrolled after install (README.md).
  # /boot is Windows' 800 MB EFI partition, shared; the boot menu lists
  # Windows too. Each generation is a ~70 MB signed image, so keep few.
  boot.lanzaboote.configurationLimit = 5;
  boot.loader.efi.canTouchEfiVariables = true;

  hardware.graphics.extraPackages = with pkgs; [
    intel-media-driver
    vpl-gpu-rt
  ];
  services.fwupd.enable = true;

  # Daily: pull main and switch to the system the homelab built. Like the
  # framework, only on mains power and at home.
  autoUpdate = {
    enable = true;
    homeNetworkOnly = true;
  };

  sops.defaultSopsFile = ./secrets/secrets.yaml;
  sops.defaultSopsFormat = "yaml";

  sops.secrets.syncthing-cert = { };
  sops.secrets.syncthing-key = { };
  # OpenCode Go API key (modules/home-manager/ai.nix merges it into opencode auth.json).
  sops.secrets.opencode-go-key.owner = username;

  users.users."${username}".openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJXhLc3vVBQPQLGlf4kMJ/WHXPlsXWzuustUwzFj/AaX erikf@arch-erik-pc"
  ];

  # Same as the framework: keep the real MAC on wired links, a stable
  # per-network one on Wi-Fi.
  networking.networkmanager.ethernet.macAddress = "permanent";
  networking.networkmanager.wifi.macAddress = "stable";

  programs.virt-manager.enable = true;
  users.groups.libvirtd.members = [ "${username}" ];
  virtualisation.libvirtd.enable = true;
  virtualisation.spiceUSBRedirection.enable = true;

  virtualisation.docker.enable = true;
  users.extraUsers."${username}".extraGroups = [ "docker" ];

  virtualisation.podman = {
    enable = true;
    dockerCompat = false;
    defaultNetwork.settings.dns_enabled = true;
  };

  # Logs and metrics to the homelab (modules/nixos/observability).
  observability = {
    enable = true;
    probes.time-agent = "http://127.0.0.1:5600/health";
  };

  services.xserver.xkb = {
    variant = "";
    layout = "us";
  };

  home-manager = {
    extraSpecialArgs = {
      inherit
        inputs
        hostName
        username
        otherPkgs
        ;
    };
    users."${username}" = import ./home.nix;
  };

  environment.systemPackages = with pkgs; [ batmon ];

  # Installed fresh in November 2026 (the shared default is the pc's 24.11).
  system.stateVersion = lib.mkForce "26.05";
}
