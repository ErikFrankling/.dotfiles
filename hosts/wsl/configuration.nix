{
  config,
  pkgs,
  inputs,
  hostName,
  lib,
  username,
  ...
}:

{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ../../modules/nixos
    # ../../modules/nixos/openvpn.nix
    #../../modules/nixos/laptop.nix
    # ../../modules/nixos/desktop.nix
    #../../modules/nixos/game.nix
    inputs.home-manager.nixosModules.default
  ];

  wsl = {
    enable = true;
    defaultUser = "${username}";
    startMenuLaunchers = true;
  };

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
    enable = true; # start the system‐wide Docker service
    rootless = {
      # make absolutely sure rootless is OFF
      enable = false;
      setSocketVariable = false;
    };
    daemon.settings = {
      # 2) Turn _on_ the userland proxy so Docker will bind ports <1024
      #    (SSH:22, HTTPS:443, etc.) on 127.0.0.1, instead of doing iptables magic
      "userland-proxy" = true;
      # ... you can also add other daemon settings here if you like
    };
  };

  users.extraUsers."${username}".extraGroups = [ "docker" ];

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
    extraSpecialArgs = { inherit inputs hostName username; };
    users = {
      "${username}" = import ./home.nix;
    };
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [ ];
}
