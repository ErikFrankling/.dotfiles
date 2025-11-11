{
  config,
  pkgs,
  inputs,
  hostName,
  lib,
  username,
  otherPkgs,
  ...
}:

{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ../../modules/nixos
    ../../modules/nixos/wsl-vpnkit.nix
    # ../../modules/nixos/openvpn.nix
    #../../modules/nixos/laptop.nix
    # ../../modules/nixos/desktop.nix
    #../../modules/nixos/game.nix
    inputs.home-manager.nixosModules.default
    inputs.nixos-wsl.nixosModules.default
  ];

  wsl = {
    enable = true;
    defaultUser = "${username}";
    # startMenuLaunchers = true;
  };

  wsl-vpnkit = {
    autoVPN = true;
    checkURL = "172.17.22.200";
  };

  nix.settings.auto-optimise-store = true;

  # Override common settings that don't work well in WSL
  services = {
    pipewire.enable = lib.mkForce false;
  };

  sops.defaultSopsFile = ./secrets.yaml;
  sops.defaultSopsFormat = "yaml";

  sops.secrets.syncthing-cert = { };
  sops.secrets.syncthing-key = { };

  # virtualisation.vmware.host.enable = true;
  # virtualisation.virtualbox.host.enable = true;
  # virtualisation.virtualbox.host.enableKvm = true;
  # virtualisation.virtualbox.host.addNetworkInterface = false;
  # users.extraGroups.vboxusers.members = [ "${username}" ];

  # programs.virt-manager.enable = true;
  # users.groups.libvirtd.members = [ "${username}" ];
  # virtualisation.libvirtd.enable = true;
  # virtualisation.spiceUSBRedirection.enable = true;

  # virtualisation.docker.enable = true;

  virtualisation.docker = {
    enable = true;
    # rootless = {
    #   # make absolutely sure rootless is OFF
    #   enable = true;
    #   setSocketVariable = true;
    # };
    daemon.settings = {
      # "userland-proxy" = true;
      bip = "192.168.99.1/24";
      iptables = false; # if needed
      default-address-pools = [
        {
          base = "192.168.100.0/16";
          size = 24;
        }
      ];
    };
  };

  users.extraUsers.${username}.extraGroups = [ "docker" ];
  users.users.${username}.extraGroups = [ "docker" ];

  # Enable Podman in configuration.nix
  # virtualisation.podman = {
  #   enable = true;
  #   # Create the default bridge network for podman
  #   defaultNetwork.settings.dns_enabled = true;
  # };
  #
  # # Optionally, create a Docker compatibility alias
  # programs.fish.shellAliases = {
  #   docker = "podman";
  # };

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ 8083 ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  networking.hostName = "${hostName}"; # Define your hostname.

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
        otherPkgs
        ;
    };
    users = {
      "${username}" = import ./home.nix;
    };
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [ ];
}
