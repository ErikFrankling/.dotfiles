{
  config,
  pkgs,
  inputs,
  hostName,
  username,
  pkgsMaster,
  ...
}:

{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ../../modules/nixos
    # ../../modules/nixos/openvpn.nix
    # ../../modules/nixos/laptop.nix
    # ../../modules/nixos/desktop.nix
    # ../../modules/nixos/game.nix
    # ../../modules/nixos/ollama.nix
    inputs.home-manager.nixosModules.default
  ];

  # # Bootloader.
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda";
  # # boot.loader.grub.device = "/dev/nvme0n1";
  boot.loader.grub.useOSProber = true;

  virtualisation.docker.enable = true;
  users.extraUsers."${username}".extraGroups = [ "docker" ];

  # nixpkgs.config.permittedInsecurePackages = [
  #   "electron-33.4.11"
  # ];

  # boot.kernelPackages = pkgs.linuxPackages_6_12;

  # boot.kernelPackages =
  #   let
  #     version = "6.12.31";
  #     kernel = pkgs.linuxKernel.kernels.linux_6_12.override {
  #       argsOverride = {
  #         inherit version;
  #         src = pkgs.fetchurl {
  #           url = "mirror://kernel/linux/kernel/v6.x/linux-${version}.tar.xz";
  #           hash = "sha256-sExbPl324KpenNHv5Sf6yZ+d05pDuX8Tsi+MqT5SS6c="; # to be filled in
  #         };
  #         modDirVersion = null; # https://github.com/NixOS/nixpkgs/blob/007e91615b8127deb57ba0b08e12542abaea1c3f/pkgs/os-specific/linux/kernel/generic.nix#L44
  #       };
  #     };
  #   in
  #   pkgs.linuxKernel.packagesFor kernel;

  sops.defaultSopsFile = ./secrets.yaml;
  sops.defaultSopsFormat = "yaml";

  sops.secrets.syncthing-cert = { };
  sops.secrets.syncthing-key = { };

  networking.hostName = "${hostName}"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # boot.loader.systemd-boot.enable = true;
  # boot.loader.efi.canTouchEfiVariables = true;

  # Configure keymap in X11
  services.xserver = {
    xkb = {
      variant = "";
      layout = "se";
    };
  };

  # Configure console keymap
  console.keyMap = "sv-latin1";

  home-manager = {
    # also pass inputs to home-manager modules
    extraSpecialArgs = {
      inherit
        inputs
        hostName
        username
        pkgsMaster
        ;
    };
    users = {
      "${username}" = import ./home.nix;
    };
  };

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [
  #   8080
  #   8081
  # ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    #  wget
  ];
}
