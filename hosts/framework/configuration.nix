{
  config,
  pkgs,
  inputs,
  hostName,
  username,
  otherPkgs,
  ...
}:

{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ../../modules/nixos
    ../../modules/nixos/openvpn.nix
    ../../modules/nixos/laptop.nix
    ../../modules/nixos/desktop.nix
    ../../modules/nixos/game.nix
    inputs.home-manager.nixosModules.default
    ../../modules/nixos/vm-host.nix
  ];

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

  sops.defaultSopsFile = ./secrets/secrets.yaml;
  sops.defaultSopsFormat = "yaml";

  sops.secrets.syncthing-cert = { };
  sops.secrets.syncthing-key = { };

  sops.secrets.openvpn = {
    format = "binary";
    # can be also set per secret
    sopsFile = ./secrets/client.ovpn;
  };

  sops.secrets.openvpn-auth = {
    format = "binary";
    sopsFile = ./secrets/openvpn-auth.txt;
  };

  virtualisation.vmware.host.enable = true;
  # virtualisation.virtualbox.host.enable = true;
  # virtualisation.virtualbox.host.enableKvm = true;
  # virtualisation.virtualbox.host.addNetworkInterface = false;
  # users.extraGroups.vboxusers.members = [ "${username}" ];

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

  # Open ports in the firewall.
  networking.firewall.allowedTCPPorts = [ 8083 ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  networking.hostName = "framework"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Enable fw-fanctrl
  hardware.fw-fanctrl.enable = true;

  # Add a custom config
  hardware.fw-fanctrl.config = {
    defaultStrategy = "slow";
    strategies = {
      "slow" = {
        fanSpeedUpdateFrequency = 2;
        movingAverageInterval = 100;
        speedCurve = [
          {
            temp = 0;
            speed = 0;
          }
          {
            temp = 50;
            speed = 0;
          }
          {
            temp = 65;
            speed = 0;
          }
          {
            temp = 70;
            speed = 15;
          }
          {
            temp = 75;
            speed = 25;
          }
          {
            temp = 80;
            speed = 30;
          }
          {
            temp = 85;
            speed = 50;
          }
          {
            temp = 90;
            speed = 70;
          }
          {
            temp = 95;
            speed = 100;
          }
        ];
      };
      "very-agile" = {
        fanSpeedUpdateFrequency = 5;
        movingAverageInterval = 30;
        speedCurve = [
          {
            temp = 0;
            speed = 15;
          }
          {
            temp = 50;
            speed = 15;
          }
          {
            temp = 65;
            speed = 35;
          }
          {
            temp = 70;
            speed = 40;
          }
          {
            temp = 75;
            speed = 50;
          }
          {
            temp = 80;
            speed = 80;
          }
          {
            temp = 85;
            speed = 100;
          }
        ];
      };
    };
  };
  # enables updating firmware without booting to bios
  services.fwupd.enable = true;

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # fix for amdgpu kernel bug https://gitlab.freedesktop.org/drm/amd/-/issues/3388
  boot.kernelParams = [ "amdgpu.dcdebugmask=0x10" ];

  # Configure keymap in X11
  services.xserver = {
    xkb = {
      variant = "";
      layout = "us";
    };
  };

  # Configure console keymap
  # console.keyMap = "sv-latin1";

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
  environment.systemPackages = with pkgs; [
    #  wget
    # swi-prolog-gui
    fw-ectool
  ];
}
